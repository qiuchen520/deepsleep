/// 记忆引擎的抽象契约（纯 Dart，不依赖 Flutter，便于单元测试）。
library;

import '../../data/models/chat_models.dart';
import '../../data/models/memory_models.dart';

/// 供记忆引擎调用的大模型接口（抽取 / 压缩 / 标题都复用它）。
abstract class LlmClient {
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.2,
    int maxTokens = 1200,
    Duration timeout = const Duration(seconds: 60),
  });
}

/// 记忆持久化抽象。App 用 SQLite 实现，测试用内存实现。
abstract class MemoryStore {
  Future<void> init();

  Future<List<MemoryItem>> listMemories({
    required String userId,
    MemoryStatus? status,
    int limit = 500,
    int offset = 0,
  });

  Future<MemoryItem?> getMemory(String id);

  Future<void> saveMemory(MemoryItem item);

  Future<void> saveMemories(List<MemoryItem> items);

  Future<void> deleteMemory(String id);

  Future<void> markAccessed(List<String> ids, DateTime at);

  Future<List<MemoryEntity>> listEntities({
    required String userId,
    int limit = 500,
  });

  Future<void> saveEntities(List<MemoryEntity> entities);

  Future<List<MemoryRelation>> listRelations({
    required String userId,
    int limit = 500,
  });

  Future<void> saveRelations(List<MemoryRelation> relations);

  Future<void> saveEpisode(Episode episode);

  Future<List<Episode>> listEpisodes({
    required String userId,
    int limit = 50,
  });

  Future<MemoryStats> stats(String userId);

  Future<void> clearUser(String userId);
}

/// 检索结果：可直接拼进 System Prompt 的记忆块。
class MemoryContext {
  const MemoryContext({
    this.systemBlock = '',
    this.items = const <MemoryItem>[],
    this.tokens = 0,
    this.entityNames = const <String>[],
  });

  /// 已经格式化好的「【长期记忆】…」文本，空字符串表示本次没有命中。
  final String systemBlock;

  final List<MemoryItem> items;
  final int tokens;
  final List<String> entityNames;

  bool get isEmpty => items.isEmpty || systemBlock.trim().isEmpty;

  static const MemoryContext empty = MemoryContext();
}

/// 一次记忆抽取/合并的结果。
class IngestResult {
  const IngestResult({
    this.added = 0,
    this.updated = 0,
    this.superseded = 0,
    this.skipped = 0,
    this.episodeTokens = 0,
    this.entityNames = const <String>[],
    this.touched = const <MemoryItem>[],
    this.errors = const <String>[],
    this.skippedByUser = false,
  });

  final int added;
  final int updated;
  final int superseded;
  final int skipped;
  final int episodeTokens;
  final List<String> entityNames;

  /// 本次新增/更新的记忆，用于 UI 展示「已更新 N 条记忆」。
  final List<MemoryItem> touched;
  final List<String> errors;

  /// 用户关闭了记忆功能时直接返回。
  final bool skippedByUser;

  int get totalTouched => added + updated;

  bool get isEmpty => totalTouched == 0 && superseded == 0;
}

/// 上下文压缩结果。
class CompressionResult {
  const CompressionResult({
    this.applied = false,
    this.summary = '',
    this.compressedCount = 0,
    this.uptoMessageId,
    this.tokensBefore = 0,
    this.tokensAfter = 0,
    this.error,
  });

  final bool applied;
  final String summary;
  final int compressedCount;
  final String? uptoMessageId;
  final int tokensBefore;
  final int tokensAfter;
  final String? error;

  static const CompressionResult notNeeded = CompressionResult();
}

/// 记忆知识网快照（用于可视化）。
class MemoryGraphSnapshot {
  const MemoryGraphSnapshot({
    this.entities = const <MemoryEntity>[],
    this.relations = const <MemoryRelation>[],
    this.memories = const <MemoryItem>[],
  });

  final List<MemoryEntity> entities;
  final List<MemoryRelation> relations;
  final List<MemoryItem> memories;

  bool get isEmpty => entities.isEmpty && relations.isEmpty && memories.isEmpty;
}

/// 记忆引擎主接口。
///
/// 生命周期：
/// 1. 用户发消息前 -> [retrieve] 取回相关记忆，拼到 System Prompt；
/// 2. 模型回复结束后 -> [ingest] 抽取并合并新记忆；
/// 3. 上下文过长 -> [compress] 把前半段总结成摘要。
abstract class MemoryEngine {
  Future<MemoryContext> retrieve({
    required String userId,
    required String query,
    int tokenBudget = 600,
    int limit = 8,
    String? sessionId,
  });

  Future<IngestResult> ingest({
    required String userId,
    required String sessionId,
    required String userMessage,
    required String assistantMessage,
    String? userMessageId,
    String? assistantMessageId,
    bool enabled = true,
  });

  Future<CompressionResult> compress({
    required String sessionId,
    required String existingSummary,
    required List<ChatMessage> messages,
    int threshold = 4000,
    int keepRecent = 6,
    void Function(String partialSummary)? onPartial,
  });

  Future<MemoryStats> stats(String userId);

  Future<List<MemoryItem>> listMemories({
    required String userId,
    MemoryKind? kind,
    String? query,
    int limit = 200,
    int offset = 0,
  });

  Future<void> updateMemory(MemoryItem item);

  Future<void> deleteMemory(String userId, String memoryId);

  Future<MemoryGraphSnapshot> graph(String userId, {int maxNodes = 60});

  Future<void> dispose();
}
