/// DeepSeek 官方「Anthropic 兼容」接口客户端。
///
/// 作用：调用 DeepSeek 自带的联网搜索 / 网页阅读工具，而不是第三方搜索 API。
/// 协议来自官方 Web Demo（chat-demo-v0.1.1）的实测行为：
///
/// ```
/// POST https://api.deepseek.com/anthropic/v1/messages
/// x-api-key: <API Key>
/// Accept: text/event-stream
/// {
///   "model": "deepseek-flash",
///   "system": "...",
///   "messages": [...],
///   "thinking": {"type": "enabled"},
///   "safety_check": {"level": "high"},
///   "tools": [
///     {"type": "deepseek_read_url", "name": "deepseek_read_url"},
///     {"type": "deepseek_web_search", "name": "deepseek_web_search"}
///   ],
///   "stream": true
/// }
/// ```
///
/// 流式事件与 Anthropic Messages API 类似：message_start / content_block_* /
/// message_delta / message_stop；搜索结果是 `web_search_tool_result` 内容块。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models/chat_models.dart';
import 'contracts.dart';
import 'sse_parser.dart';

class DeepSeekAnthropicClient implements ChatApi {
  DeepSeekAnthropicClient({
    required String Function() apiKeyProvider,
    required String Function() baseUrlProvider,
    http.Client? httpClient,
  })  : _apiKeyProvider = apiKeyProvider,
        _baseUrlProvider = baseUrlProvider,
        _httpClient = httpClient;

  final String Function() _apiKeyProvider;
  final String Function() _baseUrlProvider;
  final http.Client? _httpClient;

  /// DeepSeek 自营搜索使用的模型（官方 Demo 同款）。
  static const String searchModel = 'deepseek-flash';

  static const Duration _connectTimeout = Duration(seconds: 30);
  static const Duration _idleTimeout = Duration(seconds: 150);

  String get _apiKey => _apiKeyProvider().trim();

  String get _baseUrl {
    var base = _baseUrlProvider().trim();
    if (base.isEmpty) base = 'https://api.deepseek.com';
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return base;
  }

  @override
  Stream<ChatStreamEvent> streamChat(ChatRequest request) async* {
    if (_apiKey.isEmpty) {
      throw const ApiException(ApiErrorKind.auth, 'API Key 为空');
    }
    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    try {
      final body = _buildBody(request);
      final httpRequest = http.Request(
        'POST',
        Uri.parse('$_baseUrl/anthropic/v1/messages'),
      )
        ..headers.addAll(<String, String>{
          'x-api-key': _apiKey,
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..bodyBytes = utf8.encode(jsonEncode(body));

      http.StreamedResponse response;
      try {
        response = await client.send(httpRequest).timeout(_connectTimeout);
      } catch (error) {
        throw _mapNetworkError(error);
      }

      if (response.statusCode != 200) {
        final text = await _readBody(response);
        throw _httpError(response.statusCode, text);
      }

      final parser = SseLineParser();
      var promptTokens = 0;
      var completionTokens = 0;
      var sawText = false;
      final searchHits = <SearchHit>[];

      try {
        await for (final chunk
            in response.stream.transform(utf8.decoder).timeout(_idleTimeout)) {
          for (final data in parser.feed(chunk)) {
            if (isSseDone(data)) continue;
            Map<String, dynamic> event;
            try {
              final decoded = jsonDecode(data);
              if (decoded is! Map<String, dynamic>) continue;
              event = decoded;
            } catch (_) {
              continue;
            }

            if (event['type'] == 'error') {
              final err = event['error'];
              final message = err is Map ? '${err['message'] ?? ''}' : '$err';
              throw ApiException(ApiErrorKind.unknown, message);
            }

            switch (event['type']) {
              case 'message_start':
                final message = event['message'];
                if (message is Map) {
                  final usage = message['usage'];
                  if (usage is Map) {
                    promptTokens =
                        (usage['input_tokens'] as num?)?.toInt() ?? 0;
                  }
                }
                break;

              case 'content_block_start':
                final block = event['content_block'];
                if (block is! Map) break;
                final type = block['type'];
                if (type == 'text') {
                  final text = '${block['text'] ?? ''}';
                  if (text.isNotEmpty) {
                    sawText = true;
                    yield ChatStreamEvent(
                      type: StreamEventType.content,
                      text: text,
                    );
                  }
                  _collectCitations(block, searchHits);
                } else if (type == 'thinking') {
                  final thinking = '${block['thinking'] ?? ''}';
                  if (thinking.isNotEmpty) {
                    yield ChatStreamEvent(
                      type: StreamEventType.reasoning,
                      text: thinking,
                    );
                  }
                } else if (type == 'web_search_tool_result') {
                  final added = _collectSearchResults(block);
                  if (added.isNotEmpty) {
                    searchHits.addAll(added);
                    yield ChatStreamEvent(
                      type: StreamEventType.searchResults,
                      searchHits: List<SearchHit>.unmodifiable(searchHits),
                    );
                  }
                } else if (type == 'server_tool_use') {
                  final input = block['input'];
                  if (input is Map && input['action'] == 'search') {
                    final queries = (input['queries'] as List<dynamic>? ?? const [])
                        .whereType<String>()
                        .where((e) => e.trim().isNotEmpty)
                        .toList();
                    if (queries.isNotEmpty) {
                      yield ChatStreamEvent(
                        type: StreamEventType.searchQuery,
                        queries: queries,
                      );
                    }
                  }
                } else if (type == 'web_fetch_tool_result') {
                  final pages = _collectVisitedPages(block);
                  if (pages.isNotEmpty) {
                    yield ChatStreamEvent(
                      type: StreamEventType.pagesVisited,
                      visitedPages: pages,
                    );
                  }
                }
                break;

              case 'content_block_delta':
                final delta = event['delta'];
                if (delta is! Map) break;
                final deltaType = delta['type'];
                if (deltaType == 'text_delta') {
                  final text = '${delta['text'] ?? ''}';
                  if (text.isNotEmpty) {
                    sawText = true;
                    yield ChatStreamEvent(
                      type: StreamEventType.content,
                      text: text,
                    );
                  }
                } else if (deltaType == 'thinking_delta') {
                  final thinking = '${delta['thinking'] ?? ''}';
                  if (thinking.isNotEmpty) {
                    yield ChatStreamEvent(
                      type: StreamEventType.reasoning,
                      text: thinking,
                    );
                  }
                } else if (deltaType == 'citations_delta') {
                  final citation = delta['citation'];
                  if (citation is Map) {
                    final hit = _citationToHit(citation);
                    if (hit != null) {
                      searchHits.add(hit);
                      yield ChatStreamEvent(
                        type: StreamEventType.searchResults,
                        searchHits: List<SearchHit>.unmodifiable(searchHits),
                      );
                    }
                  }
                }
                break;

              case 'message_delta':
                final usage = event['usage'];
                if (usage is Map) {
                  completionTokens =
                      (usage['output_tokens'] as num?)?.toInt() ?? 0;
                }
                break;

              case 'message_stop':
                break;

              default:
                break;
            }
          }
        }
        for (final data in parser.flush()) {
          if (isSseDone(data)) continue;
          // 极少见：最后一帧没有换行，按普通 JSON 处理一次。
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic> &&
                decoded['type'] == 'content_block_delta') {
              final delta = decoded['delta'];
              if (delta is Map && delta['type'] == 'text_delta') {
                final text = '${delta['text'] ?? ''}';
                if (text.isNotEmpty) {
                  sawText = true;
                  yield ChatStreamEvent(
                    type: StreamEventType.content,
                    text: text,
                  );
                }
              }
            }
          } catch (_) {}
        }
      } catch (error) {
        throw _mapNetworkError(error);
      }

      if (!sawText) {
        yield const ChatStreamEvent(
          type: StreamEventType.error,
          errorMessage: '没有收到有效回复，请稍后重试',
        );
        return;
      }

      yield ChatStreamEvent(
        type: StreamEventType.usage,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
      yield ChatStreamEvent.done;
    } finally {
      if (ownsClient) client.close();
    }
  }

  Map<String, dynamic> _buildBody(ChatRequest request) {
    String system = '';
    final messages = <Map<String, dynamic>>[];
    for (final turn in request.messages) {
      if (turn.role == 'system') {
        system = system.isEmpty ? turn.content : '$system\n${turn.content}';
        continue;
      }
      final role = turn.role == 'assistant' ? 'assistant' : 'user';
      messages.add(<String, dynamic>{
        'role': role,
        'content': <Map<String, String>>[
          <String, String>{'type': 'text', 'text': turn.content},
        ],
      });
    }

    final tools = <Map<String, String>>[
      <String, String>{
        'type': 'deepseek_read_url',
        'name': 'deepseek_read_url',
      },
      if (request.useServerSearch)
        <String, String>{
          'type': 'deepseek_web_search',
          'name': 'deepseek_web_search',
        },
    ];

    return <String, dynamic>{
      'model': searchModel,
      'system': system.isEmpty ? '该助手为DeepSeek，由深度求索公司创造。' : system,
      'messages': messages,
      'thinking': <String, String>{
        'type': request.deepThinking ? 'enabled' : 'disabled',
      },
      'safety_check': <String, String>{'level': 'high'},
      'tools': tools,
      'stream': true,
    };
  }

  List<SearchHit> _collectVisitedPages(Map<dynamic, dynamic> block) {
    final content = block['content'];
    final pages = <SearchHit>[];
    if (content is List) {
      for (final item in content) {
        if (item is Map && item['type'] == 'web_fetch_result') {
          final url = '${item['url'] ?? ''}'.trim();
          final inner = item['content'];
          final title = inner is Map ? '${inner['title'] ?? url}' : url;
          if (url.isNotEmpty) {
            pages.add(SearchHit(title: title.trim(), url: url, snippet: ''));
          }
        }
      }
    } else if (content is Map && content['type'] == 'web_fetch_result') {
      final url = '${content['url'] ?? ''}'.trim();
      final inner = content['content'];
      final title = inner is Map ? '${inner['title'] ?? url}' : url;
      if (url.isNotEmpty) {
        pages.add(SearchHit(title: title.trim(), url: url, snippet: ''));
      }
    }
    return pages;
  }

  List<SearchHit> _collectSearchResults(Map<dynamic, dynamic> block) {
    final content = block['content'];
    if (content is! List) return const <SearchHit>[];
    final hits = <SearchHit>[];
    for (final item in content) {
      if (item is! Map) continue;
      if (item['type'] != 'web_search_result') continue;
      final url = '${item['url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      hits.add(
        SearchHit(
          title: '${item['title'] ?? url}'.trim(),
          url: url,
          snippet: '${item['snippet'] ?? item['page_age'] ?? ''}'.trim(),
          engine: 'deepseek',
        ),
      );
    }
    return hits;
  }

  void _collectCitations(Map<dynamic, dynamic> block, List<SearchHit> hits) {
    final citations = block['citations'];
    if (citations is! List) return;
    for (final item in citations) {
      if (item is! Map) continue;
      final hit = _citationToHit(item);
      if (hit != null) hits.add(hit);
    }
  }

  SearchHit? _citationToHit(Map<dynamic, dynamic> citation) {
    final url = '${citation['url'] ?? ''}'.trim();
    if (url.isEmpty) return null;
    return SearchHit(
      title: '${citation['title'] ?? url}'.trim(),
      url: url,
      snippet: '${citation['cited_text'] ?? ''}'.trim(),
      engine: 'deepseek',
    );
  }

  Future<String> _readBody(http.StreamedResponse response) async {
    try {
      final bytes = await response.stream.toBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  ApiException _mapNetworkError(Object error) {
    if (error is ApiException) return error;
    if (error is TimeoutException) {
      return const ApiException(ApiErrorKind.network, '请求超时');
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Connection')) {
      return ApiException(ApiErrorKind.network, text);
    }
    return ApiException(ApiErrorKind.unknown, text);
  }

  ApiException _httpError(int statusCode, String body) {
    String message = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          message = '${error['message'] ?? ''}';
        } else if (decoded['message'] != null) {
          message = '${decoded['message']}';
        }
      }
    } catch (_) {
      message = body;
    }
    final lower = message.toLowerCase();
    switch (statusCode) {
      case 401:
      case 403:
        return ApiException(ApiErrorKind.auth, message, statusCode: statusCode);
      case 402:
        return const ApiException(
          ApiErrorKind.insufficientBalance,
          '账户余额不足',
          statusCode: 402,
        );
      case 429:
        return ApiException(
          ApiErrorKind.rateLimited,
          '请求过于频繁',
          statusCode: statusCode,
        );
      case 500:
      case 502:
      case 503:
      case 504:
        return ApiException(
          ApiErrorKind.serverBusy,
          '服务器繁忙',
          statusCode: statusCode,
        );
    }
    if (lower.contains('insufficient balance') || lower.contains('余额不足')) {
      return const ApiException(
        ApiErrorKind.insufficientBalance,
        '账户余额不足',
      );
    }
    return ApiException(
      ApiErrorKind.invalidRequest,
      message,
      statusCode: statusCode,
    );
  }

  // 该客户端只负责搜索模式的流式对话；非流式能力由标准 OpenAI 客户端提供。
  @override
  Future<String> completeText({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.3,
    int maxTokens = 1200,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw const ApiException(
      ApiErrorKind.invalidRequest,
      'Anthropic 兼容客户端不支持非流式补全',
    );
  }

  @override
  Future<List<String>> listModels() async {
    throw const ApiException(
      ApiErrorKind.invalidRequest,
      'Anthropic 兼容客户端不支持模型列表',
    );
  }

  @override
  Future<void> validateApiKey() async {
    throw const ApiException(
      ApiErrorKind.invalidRequest,
      'Anthropic 兼容客户端不支持 Key 校验',
    );
  }

  @override
  Future<String> generateTitle({
    required String firstUserMessage,
    String? firstAssistantMessage,
  }) async {
    return '';
  }

  @override
  void dispose() {}
}
