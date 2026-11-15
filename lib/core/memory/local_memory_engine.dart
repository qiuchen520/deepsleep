/// 本地记忆引擎（纯 Dart）：
/// 用本地知识网（记忆 + 实体 + 关系）实现 [MemoryEngine]。
///
/// 流水线：
/// 1. [retrieve]：active 记忆 -> 关键词 + 图扩展打分 -> token 预算贪心装填
///    -> 格式化成 `【长期记忆】` 块 -> 标记访问；
/// 2. [ingest]：对话文本 -> LLM 抽取 JSON -> 解析 -> 去重/冲突取代 -> 落库
///    -> 更新知识图 -> 保存 Episode 原文；
/// 3. [compress]：token 超阈值时把较早消息压成中文摘要。
///
/// 设计约束：任何异常都不能抛给调用方，错误进 `errors` / 打日志。
library;

import '../../data/models/chat_models.dart';
import '../../data/models/memory_models.dart';
import '../constants.dart';
import '../utils/ids.dart';
import '../utils/token_estimator.dart';
import 'contracts.dart';
import 'extraction.dart';
import 'memory_graph.dart';
import 'memory_prompts.dart';
import 'memory_scoring.dart';
import 'memory_utils.dart';

/// 记忆引擎的本地实现。
class LocalMemoryEngine implements MemoryEngine {
  LocalMemoryEngine({
    required MemoryStore store,
    required LlmClient llm,
    int defaultTokenBudget = 600,
    String? extractionModel,
    void Function(String message)? onLog,
  })  : _store = store,
        _llm = llm,
        _defaultTokenBudget = defaultTokenBudget,
        _extractionModel = extractionModel,
        _onLog = onLog;

  final MemoryStore _store;
  final LlmClient _llm;
  final int _defaultTokenBudget;
  final String? _extractionModel;
  final void Function(String message)? _onLog;

  bool _disposed = false;

  static const int _episodeTokenBudget = 1500;

  /// 是否已释放（幂等 dispose）。
  bool get isDisposed => _disposed;

  @override
  Future<MemoryContext> retrieve({
    required String userId,
    required String query,
    int tokenBudget = 600,
    int limit = 8,
    String? sessionId,
  }) async {
    if (_disposed || limit <= 0) return MemoryContext.empty;
    final budget = _resolveBudget(tokenBudget);
    if (budget <= 0) return MemoryContext.empty;
    final queryTokens = tokenSet(query);
    if (queryTokens.isEmpty) return MemoryContext.empty;

    try {
      final now = DateTime.now();
      final memories = await _store.listMemories(
        userId: userId,
        status: MemoryStatus.active,
        limit: 1000,
      );
      if (memories.isEmpty) return MemoryContext.empty;

      var graphEntityKeys = const <String>{};
      try {
        final entities = await _store.listEntities(userId: userId, limit: 1000);
        final relations =
            await _store.listRelations(userId: userId, limit: 1000);
        graphEntityKeys = expandQueryEntities(
          query: query,
          queryTokens: queryTokens,
          entities: entities,
          relations: relations,
        );
      } catch (error) {
        _log('记忆图扩展失败: $error');
      }

      final ranked = rankMemories(
        memories: memories,
        queryTokens: queryTokens,
        graphEntityKeys: graphEntityKeys,
        now: now,
      );

      final selected = <MemoryItem>[];
      var usedTokens = estimateTokens(memoryBlockHeader);
      for (final scored in ranked) {
        if (selected.length >= limit) break;
        if (!_isRelevant(scored)) continue;
        final cost = estimateTokens(formatMemoryLine(scored.item));
        if (usedTokens + cost > budget) continue;
        usedTokens += cost;
        selected.add(scored.item);
      }
      if (selected.isEmpty) return MemoryContext.empty;

      // 统一走 formatMemoryBlock：按 kind 分组、重要度倒序，格式固定。
      final block = formatMemoryBlock(selected);
      final ids = <String>[for (final item in selected) item.id];
      try {
        await _store.markAccessed(ids, now);
      } catch (error) {
        _log('记录记忆访问失败: $error');
      }

      final entityNames = <String>{
        for (final item in selected) ...item.entities,
      }.toList()
        ..sort();
      return MemoryContext(
        systemBlock: block,
        items: selected,
        tokens: estimateTokens(block),
        entityNames: entityNames,
      );
    } catch (error) {
      _log('检索记忆失败: $error');
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
    if (_disposed) {
      return const IngestResult(errors: <String>['记忆引擎已释放']);
    }
    if (!enabled) return const IngestResult(skippedByUser: true);

    final errors = <String>[];
    final now = DateTime.now();
    try {
      final existing = await _store.listMemories(
        userId: userId,
        status: MemoryStatus.active,
        limit: 500,
      );
      final raw = await _llm.complete(
        systemPrompt: memoryExtractionSystemPrompt,
        userPrompt: buildMemoryExtractionPrompt(
          userMessage: userMessage,
          assistantMessage: assistantMessage,
          existingMemories: _topForPrompt(existing),
        ),
        model: _extractionModel,
        temperature: 0.1,
        maxTokens: 1500,
      );
      final parsed = ParsedExtraction.parse(raw);
      errors.addAll(parsed.errors);

      final episodeTokens = await _saveEpisode(
        userId: userId,
        sessionId: sessionId,
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        now: now,
        errors: errors,
      );

      if (parsed.memories.isEmpty) {
        return IngestResult(
          episodeTokens: episodeTokens,
          errors: errors,
        );
      }

      final decision = buildMergeDecision(
        userId: userId,
        extraction: parsed,
        existingMemories: existing,
        now: now,
        sessionId: sessionId,
        messageId: assistantMessageId ?? userMessageId,
      );
      if (decision.toSave.isNotEmpty) {
        await _store.saveMemories(decision.toSave);
      }

      final entityNames = <String>{...decision.entityNames};
      try {
        final existingEntities =
            await _store.listEntities(userId: userId, limit: 1000);
        final existingRelations =
            await _store.listRelations(userId: userId, limit: 1000);
        final graphUpdate = buildGraphUpdate(
          userId: userId,
          existingEntities: existingEntities,
          existingRelations: existingRelations,
          extraction: parsed,
          now: now,
        );
        if (graphUpdate.entities.isNotEmpty) {
          await _store.saveEntities(graphUpdate.entities);
        }
        if (graphUpdate.relations.isNotEmpty) {
          await _store.saveRelations(graphUpdate.relations);
        }
        for (final entity in graphUpdate.entities) {
          entityNames.add(entity.name);
        }
      } catch (error) {
        errors.add('知识图更新失败: $error');
      }

      final sortedNames = entityNames.toList()..sort();
      return IngestResult(
        added: decision.added,
        updated: decision.updated,
        superseded: decision.superseded,
        skipped: decision.skipped,
        episodeTokens: episodeTokens,
        entityNames: sortedNames,
        touched: decision.touched,
        errors: errors,
      );
    } catch (error) {
      errors.add('记忆抽取失败: $error');
      return IngestResult(errors: errors);
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
    if (_disposed) return const CompressionResult();
    if (messages.isEmpty) return CompressionResult.notNeeded;

    var tokensBefore = 0;
    for (final message in messages) {
      tokensBefore += estimateMessageTokens(
        message.content,
        reasoning: message.reasoning,
      );
    }
    if (tokensBefore <= threshold) return CompressionResult.notNeeded;

    final keep = keepRecent < 0 ? 0 : keepRecent;
    if (messages.length <= keep) return CompressionResult.notNeeded;
    final compressedCount = messages.length - keep;
    final toCompress = messages.sublist(0, compressedCount);
    final recent = messages.sublist(compressedCount);

    try {
      final rawSummary = await _llm.complete(
        systemPrompt: conversationSummarySystemPrompt,
        userPrompt: buildConversationSummaryPrompt(
          existingSummary: existingSummary,
          messages: toCompress,
        ),
        model: _extractionModel,
        temperature: 0.2,
        maxTokens: 900,
      );
      final summary =
          truncateToTokens(rawSummary.trim(), AppInfo.summaryTokenBudget);
      if (summary.isEmpty) {
        return CompressionResult(
          tokensBefore: tokensBefore,
          tokensAfter: tokensBefore,
          error: '摘要模型返回为空',
        );
      }
      if (onPartial != null) onPartial(summary);

      var tokensAfter = estimateTokens(summary) + perMessageOverhead;
      for (final message in recent) {
        tokensAfter += estimateMessageTokens(
          message.content,
          reasoning: message.reasoning,
        );
      }
      return CompressionResult(
        applied: true,
        summary: summary,
        compressedCount: compressedCount,
        uptoMessageId: toCompress.last.id,
        tokensBefore: tokensBefore,
        tokensAfter: tokensAfter,
      );
    } catch (error) {
      return CompressionResult(
        tokensBefore: tokensBefore,
        tokensAfter: tokensBefore,
        error: '上下文压缩失败: $error',
      );
    }
  }

  @override
  Future<MemoryStats> stats(String userId) async {
    try {
      return await _store.stats(userId);
    } catch (error) {
      _log('读取记忆统计失败: $error');
      return const MemoryStats();
    }
  }

  @override
  Future<List<MemoryItem>> listMemories({
    required String userId,
    MemoryKind? kind,
    String? query,
    int limit = 200,
    int offset = 0,
  }) async {
    try {
      final all = await _store.listMemories(userId: userId, limit: 2000);
      final queryText = (query ?? '').trim().toLowerCase();
      final queryTokens = tokenSet(queryText);
      final filtered = <MemoryItem>[];
      for (final item in all) {
        if (kind != null && item.kind != kind) continue;
        if (queryText.isNotEmpty && !_matchesQuery(item, queryText, queryTokens)) {
          continue;
        }
        filtered.add(item);
      }
      filtered.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        final byImportance = b.importance.compareTo(a.importance);
        if (byImportance != 0) return byImportance;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      final start = offset < 0 ? 0 : offset;
      if (start >= filtered.length || limit <= 0) return const <MemoryItem>[];
      final end = start + limit;
      return filtered.sublist(
        start,
        end > filtered.length ? filtered.length : end,
      );
    } catch (error) {
      _log('列出记忆失败: $error');
      return const <MemoryItem>[];
    }
  }

  @override
  Future<void> updateMemory(MemoryItem item) async {
    if (_disposed) return;
    try {
      final keywords = item.keywords.isEmpty
          ? extractKeywords(item.content)
          : item.keywords;
      await _store.saveMemory(
        item.copyWith(
          updatedAt: DateTime.now(),
          keywords: keywords,
          fingerprint: Ids.fingerprint(item.content),
        ),
      );
    } catch (error) {
      _log('更新记忆失败: $error');
    }
  }

  @override
  Future<void> deleteMemory(String userId, String memoryId) async {
    if (_disposed) return;
    try {
      await _store.deleteMemory(memoryId);
    } catch (error) {
      _log('删除记忆失败: $error');
    }
  }

  @override
  Future<MemoryGraphSnapshot> graph(String userId, {int maxNodes = 60}) async {
    if (_disposed) return const MemoryGraphSnapshot();
    try {
      final memories = await _store.listMemories(
        userId: userId,
        status: MemoryStatus.active,
        limit: 1000,
      );
      final entities = await _store.listEntities(userId: userId, limit: 1000);
      final relations =
          await _store.listRelations(userId: userId, limit: 1000);
      return buildGraphSnapshot(
        memories: memories,
        entities: entities,
        relations: relations,
        maxNodes: maxNodes,
      );
    } catch (error) {
      _log('构建记忆图失败: $error');
      return const MemoryGraphSnapshot();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
  }

  // -------------------------------------------------------------------------
  // 内部工具
  // -------------------------------------------------------------------------

  int _resolveBudget(int requested) {
    if (_defaultTokenBudget <= 0) return requested;
    return requested < _defaultTokenBudget ? requested : _defaultTokenBudget;
  }

  bool _isRelevant(ScoredMemory scored) {
    if (scored.keywordScore > 0 || scored.graphScore > 0) return true;
    if (scored.item.pinned) return true;
    return scored.item.kind == MemoryKind.profile &&
        scored.item.importance >= 0.7;
  }

  bool _matchesQuery(
    MemoryItem item,
    String queryText,
    Set<String> queryTokens,
  ) {
    final haystack =
        '${item.content} ${item.keywords.join(' ')} ${item.entities.join(' ')}'
            .toLowerCase();
    if (haystack.contains(queryText)) return true;
    if (queryTokens.isEmpty) return false;
    final overlap = keywordOverlap(
      queryTokens,
      <String>[...item.keywords, ...item.entities],
    );
    if (overlap > 0) return true;
    for (final token in queryTokens) {
      if (textMatchesToken(item.content, token)) return true;
    }
    return false;
  }

  List<MemoryItem> _topForPrompt(List<MemoryItem> memories) {
    final sorted = <MemoryItem>[...memories];
    sorted.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final byImportance = b.importance.compareTo(a.importance);
      if (byImportance != 0) return byImportance;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted.take(20).toList();
  }

  Future<int> _saveEpisode({
    required String userId,
    required String sessionId,
    required String userMessage,
    required String assistantMessage,
    required DateTime now,
    required List<String> errors,
  }) async {
    try {
      final raw = '用户：${userMessage.trim()}\n助手：${assistantMessage.trim()}';
      final content = truncateToTokens(raw, _episodeTokenBudget);
      final tokens = estimateTokens(content);
      await _store.saveEpisode(
        Episode(
          id: Ids.newId('ep'),
          userId: userId,
          sessionId: sessionId,
          content: content,
          createdAt: now,
          tokens: tokens,
        ),
      );
      return tokens;
    } catch (error) {
      errors.add('保存原始片段失败: $error');
      return 0;
    }
  }

  void _log(String message) {
    final logger = _onLog;
    if (logger == null) return;
    try {
      logger(message);
    } catch (_) {
      // 日志回调自身的异常不应影响主流程。
      return;
    }
  }
}
