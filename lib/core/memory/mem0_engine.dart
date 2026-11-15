/// mem0 云平台记忆后端（实验特性）。
///
/// 说明：本地知识网是默认后端；当用户在设置里切到 mem0 并填入 API Key 时，
/// 记忆的抽取 / 检索 / 增删改交由 mem0 托管，会话与压缩仍在本地完成。
///
/// mem0 REST 约定：
/// - Header: `Authorization: Token <API_KEY>`
/// - 写入: POST /v1/memories/        {messages, user_id, metadata}
/// - 检索: POST /v1/memories/search/ {query, user_id, limit}
/// - 列表: GET  /v1/memories/?user_id=xxx
/// - 更新: PUT  /v1/memories/{id}/
/// - 删除: DELETE /v1/memories/{id}/
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/token_estimator.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/memory_models.dart';
import '../memory/contracts.dart';

class Mem0MemoryEngine implements MemoryEngine {
  Mem0MemoryEngine({
    required String Function() apiKeyProvider,
    required String Function() baseUrlProvider,
    required LlmClient llm,
    http.Client? httpClient,
  })  : _apiKeyProvider = apiKeyProvider,
        _baseUrlProvider = baseUrlProvider,
        _llm = llm,
        _http = httpClient ?? http.Client();

  final String Function() _apiKeyProvider;
  final String Function() _baseUrlProvider;
  final LlmClient _llm;
  final http.Client _http;

  String get _apiKey => _apiKeyProvider().trim();

  String get _baseUrl {
    final raw = _baseUrlProvider().trim();
    if (raw.isEmpty) return 'https://api.mem0.ai';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  bool get isConfigured => _apiKey.isNotEmpty;

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Token $_apiKey',
        'Content-Type': 'application/json',
      };

  @override
  Future<MemoryContext> retrieve({
    required String userId,
    required String query,
    int tokenBudget = 600,
    int limit = 8,
    String? sessionId,
  }) async {
    if (!isConfigured) return MemoryContext.empty;
    try {
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/v1/memories/search/'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'query': query,
              'user_id': userId,
              'limit': limit,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 400) return MemoryContext.empty;
      final items = _parseItems(response.body, userId);
      if (items.isEmpty) return MemoryContext.empty;

      final buffer = StringBuffer('【长期记忆】');
      final used = <MemoryItem>[];
      var tokens = estimateTokens(buffer.toString());
      for (final item in items) {
        final line = '- (${item.kind.label}) ${item.content}';
        final cost = estimateTokens(line) + 1;
        if (tokens + cost > tokenBudget) break;
        buffer
          ..writeln()
          ..write(line);
        tokens += cost;
        used.add(item);
      }
      if (used.isEmpty) return MemoryContext.empty;
      return MemoryContext(
        systemBlock: buffer.toString(),
        items: used,
        tokens: tokens,
      );
    } catch (_) {
      return MemoryContext.empty;
    }
  }

  @override
  Future<IngestResult> ingest({
    required String userId,
    required String sessionId,
    required String userMessage,
    required String assistantMessage,
    String? userMessageId,
    String? assistantMessageId,
    bool enabled = true,
  }) async {
    if (!enabled || !isConfigured) {
      return const IngestResult(skippedByUser: true);
    }
    if (assistantMessage.trim().isEmpty) {
      return const IngestResult(skippedByUser: true);
    }
    try {
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/v1/memories/'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'messages': <Map<String, String>>[
                if (userMessage.trim().isNotEmpty)
                  <String, String>{'role': 'user', 'content': userMessage},
                <String, String>{
                  'role': 'assistant',
                  'content': assistantMessage,
                },
              ],
              'user_id': userId,
              'metadata': <String, dynamic>{'session_id': sessionId},
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode >= 400) {
        return IngestResult(
          errors: <String>['mem0 写入失败（HTTP ${response.statusCode}）'],
        );
      }
      return IngestResult(
        added: 1,
        episodeTokens: estimateTokens(userMessage + assistantMessage),
      );
    } catch (e) {
      return IngestResult(errors: <String>['mem0 写入失败：$e']);
    }
  }

  @override
  Future<CompressionResult> compress({
    required String sessionId,
    required String existingSummary,
    required List<ChatMessage> messages,
    int threshold = 4000,
    int keepRecent = 6,
    void Function(String partialSummary)? onPartial,
  }) async {
    if (messages.length <= keepRecent + 1) {
      return CompressionResult.notNeeded;
    }
    final tokensBefore = estimateConversationTokens(
      messages.map((m) => m.displayContent),
      extra: estimateTokens(existingSummary),
    );
    if (tokensBefore <= threshold) return CompressionResult.notNeeded;

    final cutoff = messages.length - keepRecent;
    final older = messages.sublist(0, cutoff);
    final buffer = StringBuffer();
    if (existingSummary.trim().isNotEmpty) {
      buffer
        ..writeln('已有摘要：')
        ..writeln(existingSummary.trim())
        ..writeln();
    }
    for (final msg in older) {
      final role = msg.role == MessageRole.user ? '用户' : '助手';
      final text = msg.displayContent.trim();
      if (text.isEmpty) continue;
      buffer.writeln('$role：${truncateToTokens(text, 400)}');
    }

    try {
      final summary = await _llm.complete(
        systemPrompt:
            '你是对话摘要助手。把对话压缩成简洁的中文要点，保留关键事实、偏好、'
            '未完成任务、约定与结论。不要编造，不要输出寒暄。',
        userPrompt: buffer.toString(),
        model: AppInfo.memoryModel,
        temperature: 0.2,
        maxTokens: 700,
        timeout: const Duration(seconds: 60),
      );
      final clean = summary.trim();
      final tokensAfter = estimateTokens(clean) +
          estimateConversationTokens(
            messages.sublist(cutoff).map((m) => m.displayContent),
          );
      return CompressionResult(
        applied: clean.isNotEmpty,
        summary: clean,
        compressedCount: older.length,
        uptoMessageId: older.isEmpty ? null : older.last.id,
        tokensBefore: tokensBefore,
        tokensAfter: tokensAfter,
      );
    } catch (e) {
      return CompressionResult(error: '$e');
    }
  }

  @override
  Future<MemoryStats> stats(String userId) async {
    final items = await listMemories(userId: userId, limit: 500);
    final byKind = <MemoryKind, int>{};
    for (final item in items) {
      byKind[item.kind] = (byKind[item.kind] ?? 0) + 1;
    }
    return MemoryStats(
      total: items.length,
      active: items.length,
      byKind: byKind,
      lastUpdatedAt: items.isEmpty ? null : items.first.updatedAt,
    );
  }

  @override
  Future<List<MemoryItem>> listMemories({
    required String userId,
    MemoryKind? kind,
    String? query,
    int limit = 200,
    int offset = 0,
  }) async {
    if (!isConfigured) return <MemoryItem>[];
    try {
      final uri = Uri.parse(
        '$_baseUrl/v1/memories/?user_id=${Uri.encodeQueryComponent(userId)}',
      );
      final response = await _http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 400) return <MemoryItem>[];
      var items = _parseItems(response.body, userId);
      if (kind != null) {
        items = items.where((m) => m.kind == kind).toList();
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        items = items
            .where((m) =>
                m.content.toLowerCase().contains(q) ||
                m.keywords.any((k) => k.contains(q)))
            .toList();
      }
      if (offset > 0) {
        items = items.skip(offset).toList();
      }
      return items.take(limit).toList();
    } catch (_) {
      return <MemoryItem>[];
    }
  }

  @override
  Future<void> updateMemory(MemoryItem item) async {
    if (!isConfigured) return;
    try {
      await _http
          .put(
            Uri.parse('$_baseUrl/v1/memories/${item.id}/'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{'text': item.content}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // 静默失败，UI 会通过刷新看到真实状态。
    }
  }

  @override
  Future<void> deleteMemory(String userId, String memoryId) async {
    if (!isConfigured) return;
    try {
      await _http
          .delete(
            Uri.parse('$_baseUrl/v1/memories/$memoryId/'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  @override
  Future<MemoryGraphSnapshot> graph(String userId, {int maxNodes = 60}) async {
    // mem0 不返回实体图，这里只给记忆节点，图谱页会提示「本地模式才有完整图」。
    final items = await listMemories(userId: userId, limit: maxNodes);
    return MemoryGraphSnapshot(memories: items);
  }

  @override
  Future<void> dispose() async {
    _http.close();
  }

  List<MemoryItem> _parseItems(String body, String userId) {
    try {
      final decoded = jsonDecode(body);
      List<dynamic> rawList;
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map<String, dynamic>) {
        rawList = decoded['results'] as List<dynamic>? ??
            decoded['memories'] as List<dynamic>? ??
            <dynamic>[];
      } else {
        return <MemoryItem>[];
      }
      final now = DateTime.now();
      final items = <MemoryItem>[];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final content = (map['memory'] ?? map['text'] ?? map['content'] ?? '')
            .toString()
            .trim();
        if (content.isEmpty) continue;
        final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            now;
        final updatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
            createdAt;
        final categories = (map['categories'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
        items.add(
          MemoryItem(
            id: (map['id'] ?? Ids.newId('mem0')).toString(),
            userId: userId,
            kind: _kindFromCategories(categories),
            content: content,
            keywords: _keywords(content),
            entities: const <String>[],
            importance: ((map['score'] as num?)?.toDouble() ?? 0.5)
                .clamp(0.0, 1.0)
                .toDouble(),
            confidence: 0.8,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fingerprint: Ids.fingerprint(content),
          ),
        );
      }
      return items;
    } catch (_) {
      return <MemoryItem>[];
    }
  }

  MemoryKind _kindFromCategories(List<String> categories) {
    for (final category in categories) {
      final lower = category.toLowerCase();
      if (lower.contains('preference')) return MemoryKind.preference;
      if (lower.contains('profile') || lower.contains('identity')) {
        return MemoryKind.profile;
      }
      if (lower.contains('event')) return MemoryKind.event;
      if (lower.contains('task') || lower.contains('todo')) {
        return MemoryKind.task;
      }
      if (lower.contains('relation')) return MemoryKind.relation;
    }
    return MemoryKind.fact;
  }

  List<String> _keywords(String content) {
    final tokens = content
        .toLowerCase()
        .split(RegExp(r'[^\w\u4e00-\u9fff]+'))
        .where((e) => e.length > 1)
        .take(12)
        .toList();
    return tokens;
  }
}
