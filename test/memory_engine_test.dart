/// LocalMemoryEngine 单测：检索命中 / 预算裁剪 / 抽取合并 / 压缩 / 图。
library;

import 'package:deepsleep/core/memory/local_memory_engine.dart';
import 'package:deepsleep/data/models/chat_models.dart';
import 'package:deepsleep/data/models/memory_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_test_support.dart';

MemoryItem makeItem({
  required String id,
  required String content,
  String userId = 'u1',
  MemoryKind kind = MemoryKind.fact,
  List<String> keywords = const <String>[],
  List<String> entities = const <String>[],
  double importance = 0.5,
  bool pinned = false,
  MemoryStatus status = MemoryStatus.active,
  String? subject,
  String? predicate,
  String? object,
  String fingerprint = '',
  DateTime? updatedAt,
}) {
  final time = updatedAt ?? DateTime(2026, 1, 1);
  return MemoryItem(
    id: id,
    userId: userId,
    kind: kind,
    content: content,
    keywords: keywords,
    entities: entities,
    importance: importance,
    pinned: pinned,
    status: status,
    subject: subject,
    predicate: predicate,
    object: object,
    fingerprint: fingerprint,
    createdAt: time,
    updatedAt: time,
  );
}

ChatMessage makeMessage(String id, MessageRole role, String content) {
  return ChatMessage(
    id: id,
    sessionId: 's1',
    role: role,
    content: content,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('retrieve 检索', () {
    test('关键词命中：格式化记忆块并标记访问', () async {
      final store = InMemoryStore();
      await store.saveMemories(<MemoryItem>[
        makeItem(
          id: 'm1',
          content: '用户偏好用 Dart 写 Flutter 客户端',
          kind: MemoryKind.preference,
          keywords: <String>['dart', '客户端'],
          entities: <String>['Dart'],
          importance: 0.9,
        ),
        makeItem(
          id: 'm2',
          content: '用户喜欢喝美式咖啡',
          keywords: <String>['咖啡'],
          importance: 0.4,
        ),
      ]);
      final engine = LocalMemoryEngine(
        store: store,
        llm: FakeLlmClient(),
      );

      final context = await engine.retrieve(
        userId: 'u1',
        query: 'Dart 客户端怎么写',
        tokenBudget: 200,
      );

      expect(context.isEmpty, isFalse);
      expect(context.systemBlock, startsWith('【长期记忆】\n'));
      expect(context.systemBlock, contains('用户偏好用 Dart 写 Flutter 客户端'));
      expect(
        context.systemBlock,
        contains('- (偏好) 用户偏好用 Dart 写 Flutter 客户端（重要）'),
      );
      expect(context.items.map((item) => item.id), contains('m1'));
      expect(context.items.map((item) => item.id), isNot(contains('m2')));
      expect(context.tokens, lessThanOrEqualTo(200));
      expect(store.markAccessedCalls, 1);
      expect(store.accessedIds.single, contains('m1'));
    });

    test('token 预算裁剪：不会超出预算', () async {
      final store = InMemoryStore();
      final memories = <MemoryItem>[
        for (var i = 0; i < 6; i++)
          makeItem(
            id: 'm$i',
            content: '用户偏好用 Dart 写客户端的第 $i 条记忆补充说明',
            keywords: <String>['dart'],
            importance: 0.6,
          ),
      ];
      await store.saveMemories(memories);
      final engine = LocalMemoryEngine(
        store: store,
        llm: FakeLlmClient(),
      );

      final context = await engine.retrieve(
        userId: 'u1',
        query: 'Dart',
        tokenBudget: 70,
        limit: 8,
      );

      expect(context.items, isNotEmpty);
      expect(context.items.length, lessThan(memories.length));
      expect(context.tokens, lessThanOrEqualTo(70));
      expect(context.systemBlock.split('\n').length, greaterThan(1));
    });

    test('构造器 defaultTokenBudget 生效', () async {
      final store = InMemoryStore();
      await store.saveMemories(<MemoryItem>[
        makeItem(
          id: 'm1',
          content: '用户偏好用 Dart 写客户端的补充说明文字',
          keywords: <String>['dart'],
        ),
      ]);
      final engine = LocalMemoryEngine(
        store: store,
        llm: FakeLlmClient(),
        defaultTokenBudget: 30,
      );
      final context = await engine.retrieve(userId: 'u1', query: 'Dart');
      expect(context.tokens, lessThanOrEqualTo(30));
    });

    test('没有命中时返回空上下文', () async {
      final store = InMemoryStore();
      await store.saveMemories(<MemoryItem>[
        makeItem(
          id: 'm1',
          content: '用户喜欢喝美式咖啡',
          keywords: <String>['咖啡'],
        ),
      ]);
      final engine = LocalMemoryEngine(
        store: store,
        llm: FakeLlmClient(),
      );
      final context = await engine.retrieve(
        userId: 'u1',
        query: 'Dart 客户端怎么写',
        tokenBudget: 200,
      );
      expect(context.isEmpty, isTrue);
      expect(store.markAccessedCalls, 0);
    });

    test('图扩展召回：关系邻居也能被检索到', () async {
      final store = InMemoryStore();
      final time = DateTime(2026, 1, 1);
      await store.saveEntities(<MemoryEntity>[
        MemoryEntity(
          id: 'e1',
          userId: 'u1',
          name: 'DeepSleep',
          type: 'project',
          mentionCount: 5,
          firstSeenAt: time,
          lastSeenAt: time,
        ),
        MemoryEntity(
          id: 'e2',
          userId: 'u1',
          name: 'Flutter',
          type: 'technology',
          mentionCount: 2,
          firstSeenAt: time,
          lastSeenAt: time,
        ),
      ]);
      await store.saveRelations(<MemoryRelation>[
        MemoryRelation(
          id: 'r1',
          userId: 'u1',
          sourceName: 'DeepSleep',
          relation: 'BUILT_WITH',
          targetName: 'Flutter',
          updatedAt: time,
        ),
      ]);
      await store.saveMemories(<MemoryItem>[
        makeItem(
          id: 'm1',
          content: '项目使用 Flutter 构建跨平台界面',
          entities: <String>['Flutter'],
          importance: 0.5,
        ),
      ]);
      final engine = LocalMemoryEngine(
        store: store,
        llm: FakeLlmClient(),
      );
      final context = await engine.retrieve(
        userId: 'u1',
        query: 'DeepSleep 进展',
        tokenBudget: 200,
      );
      expect(context.items.map((item) => item.id), contains('m1'));
      expect(context.entityNames, contains('Flutter'));
    });
  });

  group('ingest 抽取与合并', () {
    test('新增记忆 + 实体关系 + Episode', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient(
        extractionJson: '{"memories":[{"kind":"profile",'
            '"content":"用户在做 DeepSleep 项目","keywords":["deepsleep","项目"],'
            '"entities":["DeepSleep"],"importance":0.85,"confidence":0.9,'
            '"subject":"用户","predicate":"在做","object":"DeepSleep",'
            '"action":"add"}],'
            '"entities":[{"name":"DeepSleep","type":"project"}],'
            '"relations":[{"source":"用户","relation":"在做","target":"DeepSleep"}]}',
      );
      final engine = LocalMemoryEngine(store: store, llm: llm);

      final result = await engine.ingest(
        userId: 'u1',
        sessionId: 's1',
        userMessage: '我在做 DeepSleep 项目',
        assistantMessage: '好的，记住啦',
        assistantMessageId: 'a1',
      );

      expect(result.errors, isEmpty);
      expect(result.added, 1);
      expect(result.updated, 0);
      expect(result.episodeTokens, greaterThan(0));
      expect(result.touched, hasLength(1));
      expect(result.entityNames, contains('DeepSleep'));
      expect(store.memories, hasLength(1));
      expect(store.memories.values.single.content, contains('DeepSleep'));
      expect(store.memories.values.single.sourceSessionId, 's1');
      expect(store.entities.values.map((entity) => entity.name),
          contains('DeepSleep'));
      expect(store.relations, hasLength(1));
      expect(store.episodes, hasLength(1));
      expect(store.episodes.single.content, contains('我在做 DeepSleep 项目'));
      expect(llm.extractionCalls, 1);
      expect(llm.models.single, isNull);
    });

    test('重复内容不新增，而是更新已有记忆', () async {
      final store = InMemoryStore();
      await store.saveMemory(
        makeItem(
          id: 'm1',
          content: '用户偏好用 Dart 写客户端',
          keywords: <String>['dart'],
          importance: 0.5,
        ),
      );
      final llm = FakeLlmClient(
        extractionJson: '{"memories":[{"kind":"preference",'
            '"content":"用户偏好用 Dart 写客户端","keywords":["dart"],'
            '"importance":0.9}]}',
      );
      final engine = LocalMemoryEngine(store: store, llm: llm);

      final result = await engine.ingest(
        userId: 'u1',
        sessionId: 's1',
        userMessage: '我一般用 Dart 写客户端',
        assistantMessage: '收到',
      );

      expect(result.added, 0);
      expect(result.updated, 1);
      expect(store.memories, hasLength(1));
      expect(store.memories['m1']!.importance, closeTo(0.9, 1e-9));
    });

    test('冲突信息取代旧记忆并写入 supersededBy', () async {
      final store = InMemoryStore();
      await store.saveMemory(
        makeItem(
          id: 'old',
          content: '用户偏好用 Python 写脚本',
          kind: MemoryKind.preference,
          subject: '用户',
          predicate: '偏好语言',
          object: 'Python',
        ),
      );
      final llm = FakeLlmClient(
        extractionJson: '{"memories":[{"kind":"preference",'
            '"content":"用户偏好用 Dart 写客户端",'
            '"subject":"用户","predicate":"偏好语言","object":"Dart",'
            '"action":"supersede"}]}',
      );
      final engine = LocalMemoryEngine(store: store, llm: llm);

      final result = await engine.ingest(
        userId: 'u1',
        sessionId: 's1',
        userMessage: '我改用 Dart 了',
        assistantMessage: '好的',
      );

      expect(result.added, 1);
      expect(result.superseded, 1);
      expect(store.memories, hasLength(2));
      final oldItem = store.memories['old']!;
      expect(oldItem.status, MemoryStatus.superseded);
      expect(oldItem.supersededBy, isNotNull);
      final active = store.memories.values
          .where((item) => item.status == MemoryStatus.active)
          .toList();
      expect(active, hasLength(1));
      expect(active.single.content, contains('Dart'));
      expect(oldItem.supersededBy, active.single.id);
    });

    test('enabled=false 直接返回 skippedByUser，不调用模型', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient();
      final engine = LocalMemoryEngine(store: store, llm: llm);

      final result = await engine.ingest(
        userId: 'u1',
        sessionId: 's1',
        userMessage: '你好',
        assistantMessage: '你好',
        enabled: false,
      );

      expect(result.skippedByUser, isTrue);
      expect(result.added, 0);
      expect(llm.extractionCalls, 0);
      expect(store.episodes, isEmpty);
    });

    test('模型输出损坏 JSON 时不抛异常，写入 errors', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient(extractionJson: '这不是 JSON');
      final engine = LocalMemoryEngine(store: store, llm: llm);

      final result = await engine.ingest(
        userId: 'u1',
        sessionId: 's1',
        userMessage: '随便聊聊',
        assistantMessage: '嗯嗯',
      );

      expect(result.added, 0);
      expect(result.errors, isNotEmpty);
    });

    test('模型调用抛异常时不向上抛', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient(throwOnComplete: true);
      final engine = LocalMemoryEngine(store: store, llm: llm);

      final result = await engine.ingest(
        userId: 'u1',
        sessionId: 's1',
        userMessage: '你好',
        assistantMessage: '你好',
      );

      expect(result.added, 0);
      expect(result.errors, isNotEmpty);
    });

    test('extractionModel 透传给 LlmClient', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient();
      final engine = LocalMemoryEngine(
        store: store,
        llm: llm,
        extractionModel: 'deepseek-chat',
      );
      await engine.ingest(
        userId: 'u1',
        sessionId: 's1',
        userMessage: '你好',
        assistantMessage: '你好',
      );
      expect(llm.models.single, 'deepseek-chat');
    });
  });

  group('compress 上下文压缩', () {
    test('未达阈值返回 notNeeded', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient();
      final engine = LocalMemoryEngine(store: store, llm: llm);
      final messages = <ChatMessage>[
        makeMessage('m1', MessageRole.user, '你好'),
        makeMessage('m2', MessageRole.assistant, '你好'),
      ];
      final result = await engine.compress(
        sessionId: 's1',
        existingSummary: '',
        messages: messages,
        threshold: 4000,
        keepRecent: 6,
      );
      expect(result.applied, isFalse);
      expect(result.summary, isEmpty);
      expect(llm.summaryCalls, 0);
    });

    test('超过阈值时压缩较早消息，保留最近 keepRecent 条', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient(summary: '合并后的摘要：用户在开发 DeepSleep 项目。');
      final engine = LocalMemoryEngine(store: store, llm: llm);
      final messages = <ChatMessage>[
        for (var i = 0; i < 8; i++)
          makeMessage(
            'm$i',
            i.isEven ? MessageRole.user : MessageRole.assistant,
            '这是第 $i 条很长的历史对话内容，' * 40,
          ),
      ];
      String? partial;
      final result = await engine.compress(
        sessionId: 's1',
        existingSummary: '之前的摘要',
        messages: messages,
        threshold: 100,
        keepRecent: 2,
        onPartial: (value) => partial = value,
      );

      expect(result.applied, isTrue);
      expect(result.compressedCount, 6);
      expect(result.uptoMessageId, 'm5');
      expect(result.summary, isNotEmpty);
      expect(result.tokensBefore, greaterThan(100));
      expect(result.tokensAfter, lessThan(result.tokensBefore));
      expect(result.error, isNull);
      expect(partial, result.summary);
      expect(llm.summaryCalls, 1);
      expect(llm.userPrompts.single, contains('之前的摘要'));
    });

    test('消息数不足 keepRecent 时不压缩', () async {
      final store = InMemoryStore();
      final llm = FakeLlmClient();
      final engine = LocalMemoryEngine(store: store, llm: llm);
      final messages = <ChatMessage>[
        makeMessage('m1', MessageRole.user, '这是一段很长的内容' * 80),
      ];
      final result = await engine.compress(
        sessionId: 's1',
        existingSummary: '',
        messages: messages,
        threshold: 10,
        keepRecent: 6,
      );
      expect(result.applied, isFalse);
      expect(llm.summaryCalls, 0);
    });
  });

  group('记忆管理', () {
    test('listMemories 支持 kind / query 过滤并按重要度排序', () async {
      final store = InMemoryStore();
      await store.saveMemories(<MemoryItem>[
        makeItem(
          id: 'm1',
          content: '用户偏好用 Dart 写客户端',
          kind: MemoryKind.preference,
          keywords: <String>['dart'],
          importance: 0.9,
        ),
        makeItem(
          id: 'm2',
          content: '用户在做 DeepSleep 项目',
          kind: MemoryKind.fact,
          keywords: <String>['deepsleep'],
          importance: 0.6,
        ),
      ]);
      final engine = LocalMemoryEngine(store: store, llm: FakeLlmClient());

      final preferences = await engine.listMemories(
        userId: 'u1',
        kind: MemoryKind.preference,
      );
      expect(preferences.map((item) => item.id).toList(), <String>['m1']);

      final searched = await engine.listMemories(userId: 'u1', query: 'Dart');
      expect(searched.map((item) => item.id).toList(), <String>['m1']);

      final all = await engine.listMemories(userId: 'u1');
      expect(all.first.id, 'm1');
    });

    test('updateMemory / deleteMemory / stats', () async {
      final store = InMemoryStore();
      await store.saveMemories(<MemoryItem>[
        makeItem(id: 'm1', content: '旧内容'),
        makeItem(
          id: 'm2',
          content: '被取代的记忆',
          status: MemoryStatus.superseded,
        ),
      ]);
      final engine = LocalMemoryEngine(store: store, llm: FakeLlmClient());

      await engine.updateMemory(
        makeItem(id: 'm1', content: '用户偏好用 Dart 写客户端'),
      );
      expect(store.memories['m1']!.content, '用户偏好用 Dart 写客户端');
      expect(store.memories['m1']!.fingerprint, isNotEmpty);

      final stats = await engine.stats('u1');
      expect(stats.total, 2);
      expect(stats.active, 1);
      expect(stats.superseded, 1);

      await engine.deleteMemory('u1', 'm2');
      expect(store.memories.containsKey('m2'), isFalse);
    });

    test('graph 按 maxNodes 裁剪节点并过滤悬空边', () async {
      final store = InMemoryStore();
      final time = DateTime(2026, 1, 1);
      await store.saveEntities(<MemoryEntity>[
        MemoryEntity(
          id: 'e1',
          userId: 'u1',
          name: 'Dart',
          type: 'technology',
          mentionCount: 5,
          firstSeenAt: time,
          lastSeenAt: time,
        ),
        MemoryEntity(
          id: 'e2',
          userId: 'u1',
          name: 'Flutter',
          type: 'technology',
          mentionCount: 1,
          firstSeenAt: time,
          lastSeenAt: time,
        ),
      ]);
      await store.saveRelations(<MemoryRelation>[
        MemoryRelation(
          id: 'r1',
          userId: 'u1',
          sourceName: 'Dart',
          relation: 'RELATED_TO',
          targetName: 'Flutter',
          updatedAt: time,
        ),
      ]);
      final engine = LocalMemoryEngine(store: store, llm: FakeLlmClient());
      final snapshot = await engine.graph('u1', maxNodes: 1);
      expect(snapshot.entities, hasLength(1));
      expect(snapshot.entities.single.name, 'Dart');
      expect(snapshot.relations, isEmpty);
    });

    test('dispose 幂等，释放后 retrieve 返回空', () async {
      final store = InMemoryStore();
      final engine = LocalMemoryEngine(store: store, llm: FakeLlmClient());
      await engine.dispose();
      await engine.dispose();
      expect(engine.isDisposed, isTrue);
      final context = await engine.retrieve(userId: 'u1', query: 'Dart');
      expect(context.isEmpty, isTrue);
    });
  });
}
