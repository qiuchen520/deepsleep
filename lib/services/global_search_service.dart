/// 全局搜索：会话标题 / 聊天记录 / 记忆知识条目，分组返回并带命中位置信息。
library;

import '../core/memory/contracts.dart';
import '../data/db/app_database.dart';
import '../data/models/chat_models.dart';
import '../data/models/memory_models.dart';

class GlobalSearchHit {
  const GlobalSearchHit({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.content = '',
    this.sessionId,
    this.messageId,
    this.memoryId,
    this.updatedAt,
  });

  /// conversation / message / memory
  final String kind;
  final String title;
  final String subtitle;

  /// 命中正文（消息内容 / 记忆内容），用于关键词高亮。
  final String content;
  final String? sessionId;
  final String? messageId;
  final String? memoryId;
  final DateTime? updatedAt;
}

class GlobalSearchResult {
  const GlobalSearchResult({
    this.conversations = const <GlobalSearchHit>[],
    this.messages = const <GlobalSearchHit>[],
    this.memories = const <GlobalSearchHit>[],
  });

  final List<GlobalSearchHit> conversations;
  final List<GlobalSearchHit> messages;
  final List<GlobalSearchHit> memories;

  bool get isEmpty =>
      conversations.isEmpty && messages.isEmpty && memories.isEmpty;

  int get total => conversations.length + messages.length + memories.length;
}

class GlobalSearchService {
  GlobalSearchService({
    required AppDatabase database,
    required MemoryEngine memoryEngine,
    required String Function() userIdProvider,
  })  : _db = database,
        _engine = memoryEngine,
        _userId = userIdProvider;

  final AppDatabase _db;
  final MemoryEngine _engine;
  final String Function() _userId;

  Future<GlobalSearchResult> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const GlobalSearchResult();

    final conversationHits = <GlobalSearchHit>[];
    final messageHits = <GlobalSearchHit>[];
    final memoryHits = <GlobalSearchHit>[];

    try {
      final conversations = await _db.searchConversations(q);
      for (final c in conversations) {
        conversationHits.add(
          GlobalSearchHit(
            kind: 'conversation',
            title: c.title,
            subtitle: '对话 · ${c.messageCount} 条消息',
            content: c.title,
            sessionId: c.id,
            updatedAt: c.updatedAt,
          ),
        );
      }
    } catch (_) {}

    try {
      final messages = await _db.searchMessages(q);
      for (final m in messages) {
        final conv = await _db.getConversation(m.sessionId);
        messageHits.add(
          GlobalSearchHit(
            kind: 'message',
            title: conv?.title ?? '对话',
            subtitle: m.role == MessageRole.user ? '我' : 'DeepSeek',
            content: m.displayContent,
            sessionId: m.sessionId,
            messageId: m.id,
            updatedAt: m.createdAt,
          ),
        );
      }
    } catch (_) {}

    try {
      final memories = await _engine.listMemories(
        userId: _userId(),
        query: q,
        limit: 40,
      );
      for (final item in memories) {
        memoryHits.add(
          GlobalSearchHit(
            kind: 'memory',
            title: item.kind.label,
            subtitle: item.createdAt.toIso8601String().substring(0, 10),
            content: item.content,
            sessionId: item.sourceSessionId,
            memoryId: item.id,
            updatedAt: item.updatedAt,
          ),
        );
      }
    } catch (_) {}

    return GlobalSearchResult(
      conversations: conversationHits,
      messages: messageHits,
      memories: memoryHits,
    );
  }

  Future<List<MemoryItem>> searchMemories(String query) {
    return _engine.listMemories(
      userId: _userId(),
      query: query.trim(),
      limit: 40,
    );
  }
}
