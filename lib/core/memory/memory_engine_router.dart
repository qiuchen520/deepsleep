/// 记忆后端路由：本地知识网 / mem0 云平台之间切换。
library;

import '../../data/models/chat_models.dart';
import '../../data/models/memory_models.dart';
import 'contracts.dart';
import 'mem0_engine.dart';

class MemoryEngineRouter implements MemoryEngine {
  MemoryEngineRouter({
    required MemoryEngine local,
    required Mem0MemoryEngine mem0,
    required bool Function() useMem0,
  })  : _local = local,
        _mem0 = mem0,
        _useMem0 = useMem0;

  final MemoryEngine _local;
  final Mem0MemoryEngine _mem0;
  final bool Function() _useMem0;

  MemoryEngine get active =>
      (_useMem0() && _mem0.isConfigured) ? _mem0 : _local;

  bool get usingMem0 => _useMem0() && _mem0.isConfigured;

  @override
  Future<MemoryContext> retrieve({
    required String userId,
    required String query,
    int tokenBudget = 600,
    int limit = 8,
    String? sessionId,
  }) {
    return active.retrieve(
      userId: userId,
      query: query,
      tokenBudget: tokenBudget,
      limit: limit,
      sessionId: sessionId,
    );
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
  }) {
    return active.ingest(
      userId: userId,
      sessionId: sessionId,
      userMessage: userMessage,
      assistantMessage: assistantMessage,
      userMessageId: userMessageId,
      assistantMessageId: assistantMessageId,
      enabled: enabled,
    );
  }

  @override
  Future<CompressionResult> compress({
    required String sessionId,
    required String existingSummary,
    required List<ChatMessage> messages,
    int threshold = 4000,
    int keepRecent = 6,
    void Function(String partialSummary)? onPartial,
  }) {
    return active.compress(
      sessionId: sessionId,
      existingSummary: existingSummary,
      messages: messages,
      threshold: threshold,
      keepRecent: keepRecent,
      onPartial: onPartial,
    );
  }

  @override
  Future<MemoryStats> stats(String userId) => active.stats(userId);

  @override
  Future<List<MemoryItem>> listMemories({
    required String userId,
    MemoryKind? kind,
    String? query,
    int limit = 200,
    int offset = 0,
  }) {
    return active.listMemories(
      userId: userId,
      kind: kind,
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<void> updateMemory(MemoryItem item) => active.updateMemory(item);

  @override
  Future<void> deleteMemory(String userId, String memoryId) =>
      active.deleteMemory(userId, memoryId);

  @override
  Future<MemoryGraphSnapshot> graph(String userId, {int maxNodes = 60}) =>
      active.graph(userId, maxNodes: maxNodes);

  @override
  Future<void> dispose() async {
    await _local.dispose();
    await _mem0.dispose();
  }
}
