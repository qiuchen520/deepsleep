/// DeepSeek（OpenAI 兼容）客户端实现。
///
/// 职责：
/// - [ChatApi]：流式聊天（SSE）、非流式补全、API Key 校验、AI 标题；
/// - [LlmClient]：给记忆引擎复用非流式补全。
///
/// 错误处理约定：所有失败都以 [ApiException] 抛出（流式请求在订阅端用
/// `onError` / `try-catch` 捕获），不额外发 error 事件，UI 只需展示
/// [ApiException.friendlyMessage]，避免「错误事件 + 异常」双路径。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/memory/contracts.dart';
import 'contracts.dart';
import 'sse_parser.dart';

/// 基于 HTTP 的 DeepSeek 客户端。
///
/// ```dart
/// final client = DeepSeekClient(
///   apiKeyProvider: () => settings.apiKey,
///   baseUrlProvider: () => settings.baseUrl,
/// );
/// ```
class DeepSeekClient implements ChatApi, LlmClient {
  DeepSeekClient({
    required String Function() apiKeyProvider,
    required String Function() baseUrlProvider,
    http.Client? httpClient,
  })  : _apiKeyProvider = apiKeyProvider,
        _baseUrlProvider = baseUrlProvider,
        _httpClient = httpClient;

  final String Function() _apiKeyProvider;
  final String Function() _baseUrlProvider;

  /// 外部注入的 client（测试 / 复用连接池）；为 null 时由本类自己创建。
  final http.Client? _httpClient;

  /// 非流式请求复用的内部 client。
  http.Client? _sharedClient;

  /// 正在流式读取的、由本类创建的 client（dispose 时统一关闭）。
  final Set<http.Client> _activeStreamClients = <http.Client>{};

  bool _disposed = false;

  /// 建立连接 / 等待响应头的超时。
  static const Duration _connectTimeout = Duration(seconds: 30);

  /// 流式读取的「接收超时」：两个数据块之间超过该时长视为网络卡死。
  static const Duration _streamIdleTimeout = Duration(seconds: 120);

  /// 非流式补全默认超时。
  static const Duration _defaultTimeout = Duration(seconds: 60);

  // ---------------------------------------------------------------------------
  // ChatApi
  // ---------------------------------------------------------------------------

  @override
  Stream<ChatStreamEvent> streamChat(ChatRequest request) async* {
    _ensureUsable();
    final apiKey = _requireApiKey();
    final uri = _endpoint('/chat/completions');

    // 每次流式请求使用独立的 client：调用方取消订阅时能真正 close 掉连接，
    // 不会影响其它并发的非流式请求（例如后台记忆抽取）。
    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    if (ownsClient) _activeStreamClients.add(client);

    try {
      final body = _streamPayload(request);
      final httpRequest = http.Request('POST', uri)
        ..headers.addAll(_headers(apiKey, stream: true))
        ..bodyBytes = utf8.encode(jsonEncode(body));

      http.StreamedResponse response;
      try {
        response = await client.send(httpRequest).timeout(_connectTimeout);
      } catch (error) {
        throw _mapError(error);
      }

      if (response.statusCode != 200) {
        throw _httpError(response.statusCode, await _readBody(response));
      }

      final parser = SseLineParser();
      final assembler = _StreamAssembler();

      try {
        outer:
        await for (final chunk in response.stream
            .transform(utf8.decoder)
            .timeout(_streamIdleTimeout)) {
          for (final data in parser.feed(chunk)) {
            if (isSseDone(data)) break outer;
            for (final event in assembler.consume(data)) {
              yield event;
            }
          }
        }
        // 容错：某些服务端最后一帧没有换行符。
        for (final data in parser.flush()) {
          if (isSseDone(data)) break;
          for (final event in assembler.consume(data)) {
            yield event;
          }
        }
      } catch (error) {
        throw _mapError(error);
      }

      if (assembler.finishReason == 'content_filter') {
        throw const ApiException(
          ApiErrorKind.contentFiltered,
          '内容被安全策略过滤',
        );
      }
      if (assembler.finishReason == 'insufficient_system_resource') {
        throw const ApiException(
          ApiErrorKind.serverBusy,
          '服务器资源不足，请稍后再试',
        );
      }

      yield ChatStreamEvent.done;
    } finally {
      if (ownsClient) {
        _activeStreamClients.remove(client);
        client.close();
      }
    }
  }

  @override
  Future<String> completeText({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.3,
    int maxTokens = 1200,
    Duration timeout = _defaultTimeout,
  }) async {
    _ensureUsable();
    final apiKey = _requireApiKey();
    final usedModel = _normalizeModel(model ?? AppInfo.defaultChatModel);
    final uri = _endpoint('/chat/completions');

    final messages = <Map<String, String>>[
      if (systemPrompt.trim().isNotEmpty)
        <String, String>{'role': 'system', 'content': systemPrompt},
      <String, String>{'role': 'user', 'content': userPrompt},
    ];
    final body = <String, dynamic>{
      'model': usedModel,
      'messages': messages,
      'stream': false,
      'max_tokens': maxTokens,
      if (_supportsTemperature(usedModel)) 'temperature': temperature,
    };

    final http.Response response;
    try {
      response = await _plainClient
          .post(
            uri,
            headers: _headers(apiKey, stream: false),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (error) {
      throw _mapError(error);
    }

    final responseBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw _httpError(response.statusCode, responseBody);
    }
    return _extractMessageContent(responseBody);
  }

  @override
  Future<void> validateApiKey() async {
    _ensureUsable();
    final apiKey = _requireApiKey();
    final uri = _endpoint('/models');
    final http.Response response;
    try {
      response = await _plainClient
          .get(uri, headers: _headers(apiKey, stream: false))
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      throw _mapError(error);
    }
    if (response.statusCode != 200) {
      throw _httpError(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    }
  }

  @override
  Future<String> generateTitle({
    required String firstUserMessage,
    String? firstAssistantMessage,
  }) async {
    final fallback = _localTitle(firstUserMessage);
    if (firstUserMessage.trim().isEmpty) return fallback;

    final assistant = (firstAssistantMessage ?? '').trim();
    final prompt = StringBuffer()
      ..writeln('用户：')
      ..writeln(firstUserMessage.trim());
    if (assistant.isNotEmpty) {
      // 只截取开头，避免标题请求消耗过多 token。
      prompt
        ..writeln()
        ..writeln('助手：')
        ..writeln(
          assistant.length > 400 ? assistant.substring(0, 400) : assistant,
        );
    }

    try {
      final raw = await completeText(
        systemPrompt: '你是一个擅长起标题的助手。请用不超过 12 字的中文短语概括下面的对话主题，'
            '只输出标题本身，不要引号、序号、句号或任何解释。',
        userPrompt: prompt.toString(),
        model: AppInfo.defaultChatModel,
        temperature: 0.3,
        maxTokens: 32,
        timeout: const Duration(seconds: 20),
      );
      return _cleanTitle(raw, fallback);
    } catch (_) {
      // 标题只是锦上添花，任何失败都退回本地标题。
      return fallback;
    }
  }

  // ---------------------------------------------------------------------------
  // LlmClient
  // ---------------------------------------------------------------------------

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.2,
    int maxTokens = 1200,
    Duration timeout = _defaultTimeout,
  }) {
    return completeText(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      model: model ?? AppInfo.memoryModel,
      temperature: temperature,
      maxTokens: maxTokens,
      timeout: timeout,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sharedClient?.close();
    _sharedClient = null;
    for (final client in _activeStreamClients.toList()) {
      client.close();
    }
    _activeStreamClients.clear();
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  http.Client get _plainClient {
    if (_disposed) {
      throw const ApiException(ApiErrorKind.cancelled, '客户端已释放');
    }
    return _httpClient ?? (_sharedClient ??= http.Client());
  }

  void _ensureUsable() {
    if (_disposed) {
      throw const ApiException(ApiErrorKind.cancelled, '客户端已释放');
    }
  }

  String _requireApiKey() {
    final key = _apiKeyProvider().trim();
    if (key.isEmpty) {
      throw const ApiException(
        ApiErrorKind.auth,
        '未配置 API Key，请在设置中填写',
      );
    }
    return key;
  }

  /// 拼接接口地址，兼容 user 在末尾多写斜杠、或没写协议的情况。
  Uri _endpoint(String path) {
    var base = _baseUrlProvider().trim();
    if (base.isEmpty) base = AppInfo.defaultBaseUrl;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    try {
      return Uri.parse('$base$path');
    } on FormatException {
      throw const ApiException(
        ApiErrorKind.invalidRequest,
        'Base URL 格式不正确，请检查设置',
      );
    }
  }

  Map<String, String> _headers(String apiKey, {required bool stream}) {
    return <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': stream ? 'text/event-stream' : 'application/json',
    };
  }

  Map<String, dynamic> _streamPayload(ChatRequest request) {
    final model = _normalizeModel(request.model);
    return <String, dynamic>{
      'model': model,
      'messages': request.messages
          .map(
            (turn) => <String, String>{
              'role': turn.role,
              'content': turn.content,
            },
          )
          .toList(),
      'stream': true,
      'stream_options': <String, bool>{'include_usage': true},
      'max_tokens': request.maxTokens,
      // deepseek-reasoner 不支持 temperature，传了部分服务端会报错。
      if (_supportsTemperature(model)) 'temperature': request.temperature,
    };
  }

  String _normalizeModel(String model) {
    final trimmed = model.trim();
    return trimmed.isEmpty ? AppInfo.defaultChatModel : trimmed;
  }

  bool _supportsTemperature(String model) =>
      !model.toLowerCase().contains('reasoner');

  /// 用流式的 response body 读取错误信息（错误响应通常很小）。
  Future<String> _readBody(http.StreamedResponse response) async {
    try {
      final bytes = await response.stream
          .toBytes()
          .timeout(const Duration(seconds: 10));
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// 从非流式响应中取 `choices[0].message.content`。
  String _extractMessageContent(String body) {
    final root = _asMap(_safeJsonDecode(body));
    if (root == null) {
      throw const ApiException(ApiErrorKind.protocol, '响应解析失败');
    }
    final inlineError = _errorMessageFrom(root);
    if (inlineError != null) {
      throw ApiException(ApiErrorKind.invalidRequest, inlineError);
    }
    final choices = root['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = _asMap(choices.first);
      final message = choice == null ? null : _asMap(choice['message']);
      final content = message?['content'];
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
    }
    throw const ApiException(ApiErrorKind.protocol, '模型返回内容为空');
  }

  Object? _safeJsonDecode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  /// 从错误响应体里尽力提取可读的错误描述。
  String? _errorMessageFrom(Map<String, dynamic> root) {
    final error = _asMap(root['error']);
    final message = error?['message'] ?? root['message'];
    if (message is String && message.trim().isNotEmpty) {
      final text = message.trim();
      return text.length > 300 ? text.substring(0, 300) : text;
    }
    return null;
  }

  ApiException _httpError(int statusCode, String body) {
    final root = _asMap(_safeJsonDecode(body));
    final extracted = root == null ? null : _errorMessageFrom(root);
    final message = (extracted ?? '').trim();
    final lower = '${body.toLowerCase()}\n${message.toLowerCase()}';

    if (statusCode == 401 || statusCode == 403) {
      return ApiException(
        ApiErrorKind.auth,
        message.isEmpty ? 'API Key 无效或已过期' : message,
        statusCode: statusCode,
      );
    }
    if (statusCode == 402 ||
        lower.contains('insufficient balance') ||
        lower.contains('insufficient_balance') ||
        lower.contains('余额不足')) {
      return ApiException(
        ApiErrorKind.insufficientBalance,
        message.isEmpty ? '账户余额不足' : message,
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return ApiException(
        ApiErrorKind.rateLimited,
        message.isEmpty ? '请求过于频繁' : message,
        statusCode: statusCode,
      );
    }
    if (statusCode == 500 || statusCode == 502 || statusCode == 503 ||
        statusCode == 504) {
      return ApiException(
        ApiErrorKind.serverBusy,
        message.isEmpty ? '服务器繁忙' : message,
        statusCode: statusCode,
      );
    }
    if (statusCode == 400 || statusCode == 422) {
      if (lower.contains('content filter') ||
          lower.contains('content_filter') ||
          lower.contains('sensitive') ||
          lower.contains('敏感') ||
          lower.contains('安全')) {
        return ApiException(
          ApiErrorKind.contentFiltered,
          message.isEmpty ? '内容被安全策略过滤' : message,
          statusCode: statusCode,
        );
      }
      return ApiException(
        ApiErrorKind.invalidRequest,
        message.isEmpty ? '请求参数有误（HTTP $statusCode）' : message,
        statusCode: statusCode,
      );
    }
    if (statusCode == 404) {
      return ApiException(
        ApiErrorKind.invalidRequest,
        message.isEmpty ? '接口地址不存在，请检查 Base URL 设置' : message,
        statusCode: statusCode,
      );
    }
    if (statusCode == 408 || statusCode == 409) {
      return ApiException(
        ApiErrorKind.network,
        message.isEmpty ? '请求超时或发生冲突，请稍后重试' : message,
        statusCode: statusCode,
      );
    }
    return ApiException(
      statusCode >= 500 ? ApiErrorKind.serverBusy : ApiErrorKind.unknown,
      message.isEmpty ? '请求失败（HTTP $statusCode）' : message,
      statusCode: statusCode,
    );
  }

  ApiException _mapError(Object error) {
    if (error is ApiException) return error;
    if (error is TimeoutException) {
      return const ApiException(
        ApiErrorKind.network,
        '请求超时，请检查网络后重试',
      );
    }
    if (error is SocketException) {
      return const ApiException(
        ApiErrorKind.network,
        '网络连接失败，请检查网络',
      );
    }
    if (error is http.ClientException) {
      return const ApiException(
        ApiErrorKind.network,
        '网络连接失败，请检查网络',
      );
    }
    if (error is FormatException) {
      return const ApiException(ApiErrorKind.protocol, '响应解析失败');
    }
    return ApiException(ApiErrorKind.unknown, '请求失败：$error');
  }

  /// 本地标题兜底：取首行、去掉 Markdown 标记，最多 12 个字符。
  String _localTitle(String firstUserMessage) {
    final line = firstUserMessage
        .split('\n')
        .map((item) => item.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    final cleaned = line.replaceAll(RegExp(r'[#>*`~]'), '').trim();
    if (cleaned.isEmpty) return '新对话';
    final runes = cleaned.runes.toList();
    if (runes.length <= 12) return cleaned;
    return String.fromCharCodes(runes.take(12));
  }

  /// 清洗模型返回的标题，异常时退回 [fallback]。
  String _cleanTitle(String raw, String fallback) {
    var title = raw.trim();
    if (title.isEmpty) return fallback;
    title = title.split('\n').first.trim();
    title = title.replaceAll(RegExp(r'^[#>\-\*\s]+'), '');
    title = title.replaceAll(RegExp('["\'“”‘’《》`]'), '');
    title = title.replaceFirst(RegExp(r'^(标题|对话主题)[:：]\s*'), '');
    title = title.replaceAll(RegExp(r'[。．.!！?？,，;；:：]+$'), '').trim();
    if (title.isEmpty) return fallback;
    final runes = title.runes.toList();
    if (runes.length > 24) {
      return String.fromCharCodes(runes.take(24));
    }
    return title;
  }
}

/// 解析单个 SSE 数据帧，累积 finish_reason 并产出聊天事件。
class _StreamAssembler {
  String? finishReason;
  bool _usageEmitted = false;

  List<ChatStreamEvent> consume(String data) {
    final decoded = _decode(data);
    final events = <ChatStreamEvent>[];

    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = _asMap(choices.first);
      if (choice != null) {
        final delta = _asMap(choice['delta']);
        if (delta != null) {
          final reasoning = delta['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) {
            events.add(
              ChatStreamEvent(
                type: StreamEventType.reasoning,
                text: reasoning,
              ),
            );
          }
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            events.add(
              ChatStreamEvent(type: StreamEventType.content, text: content),
            );
          }
        }
        final reason = choice['finish_reason'];
        if (reason is String && reason.isNotEmpty) {
          finishReason = reason;
        }
      }
    }

    final usage = _asMap(decoded['usage']);
    if (usage != null && !_usageEmitted) {
      final promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
      final completionTokens = (usage['completion_tokens'] as num?)?.toInt();
      if (promptTokens != null || completionTokens != null) {
        _usageEmitted = true;
        events.add(
          ChatStreamEvent(
            type: StreamEventType.usage,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
          ),
        );
      }
    }

    return events;
  }

  Map<String, dynamic> _decode(String data) {
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      throw const ApiException(ApiErrorKind.protocol, '流式响应不是合法 JSON');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const ApiException(ApiErrorKind.protocol, '流式响应格式不正确');
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
