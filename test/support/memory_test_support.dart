/// 记忆引擎单测的公共替身（纯 Dart，不依赖 Flutter 运行时）。
library;

import 'package:deepsleep/core/memory/contracts.dart';
import 'package:deepsleep/data/models/memory_models.dart';

/// 内存版 [MemoryStore]：记录调用次数，便于断言副作用。
class InMemoryStore implements MemoryStore {
  final Map<String, MemoryItem> memories = <String, MemoryItem>{};
  final Map<String, MemoryEntity> entities = <String, MemoryEntity>{};
  final Map<String, MemoryRelation> relations = <String, MemoryRelation>{};
  final List<Episode> episodes = <Episode>[];

  int initCalls = 0;
  int markAccessedCalls = 0;
  final List<List<String>> accessedIds = <List<String>>[];

  @override
  Future<void> init() async {
    initCalls++;
  }

  @override
  Future<List<MemoryItem>> listMemories({
    required String userId,
    MemoryStatus? status,
    int limit = 500,
    int offset = 0,
  }) async {
    final list = memories.values
        .where(
          (item) =>
              item.userId == userId &&
              (status == null || item.status == status),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final start = offset < 0 ? 0 : offset;
    if (start >= list.length || limit <= 0) return <MemoryItem>[];
    return list.skip(start).take(limit).toList();
  }

  @override
  Future<MemoryItem?> getMemory(String id) async => memories[id];

  @override
  Future<void> saveMemory(MemoryItem item) async {
    memories[item.id] = item;
  }

  @override
  Future<void> saveMemories(List<MemoryItem> items) async {
    for (final item in items) {
      memories[item.id] = item;
    }
  }

  @override
  Future<void> deleteMemory(String id) async {
    memories.remove(id);
  }

  @override
  Future<void> markAccessed(List<String> ids, DateTime at) async {
    markAccessedCalls++;
    accessedIds.add(List<String>.from(ids));
    for (final id in ids) {
      final item = memories[id];
      if (item == null) continue;
      memories[id] = item.copyWith(
        lastAccessAt: at,
        accessCount: item.accessCount + 1,
      );
    }
  }

  @override
  Future<List<MemoryEntity>> listEntities({
    required String userId,
    int limit = 500,
  }) async {
    final list = entities.values
        .where((entity) => entity.userId == userId)
        .toList()
      ..sort((a, b) => b.mentionCount.compareTo(a.mentionCount));
    return list.take(limit).toList();
  }

  @override
  Future<void> saveEntities(List<MemoryEntity> items) async {
    for (final entity in items) {
      entities[entity.id] = entity;
    }
  }

  @override
  Future<List<MemoryRelation>> listRelations({
    required String userId,
    int limit = 500,
  }) async {
    final list = relations.values
        .where((relation) => relation.userId == userId)
        .toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    return list.take(limit).toList();
  }

  @override
  Future<void> saveRelations(List<MemoryRelation> items) async {
    for (final relation in items) {
      relations[relation.id] = relation;
    }
  }

  @override
  Future<void> saveEpisode(Episode episode) async {
    episodes.add(episode);
  }

  @override
  Future<List<Episode>> listEpisodes({
    required String userId,
    int limit = 50,
  }) async {
    final list = episodes.where((episode) => episode.userId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(limit).toList();
  }

  @override
  Future<MemoryStats> stats(String userId) async {
    final userMemories =
        memories.values.where((item) => item.userId == userId).toList();
    final byKind = <MemoryKind, int>{};
    DateTime? lastUpdatedAt;
    for (final item in userMemories) {
      byKind[item.kind] = (byKind[item.kind] ?? 0) + 1;
      final previous = lastUpdatedAt;
      if (previous == null || item.updatedAt.isAfter(previous)) {
        lastUpdatedAt = item.updatedAt;
      }
    }
    return MemoryStats(
      total: userMemories.length,
      active: userMemories
          .where((item) => item.status == MemoryStatus.active)
          .length,
      superseded: userMemories
          .where((item) => item.status == MemoryStatus.superseded)
          .length,
      entities:
          entities.values.where((entity) => entity.userId == userId).length,
      relations:
          relations.values.where((relation) => relation.userId == userId).length,
      episodes: episodes.where((episode) => episode.userId == userId).length,
      byKind: byKind,
      lastUpdatedAt: lastUpdatedAt,
    );
  }

  @override
  Future<void> clearUser(String userId) async {
    memories.removeWhere((_, item) => item.userId == userId);
    entities.removeWhere((_, entity) => entity.userId == userId);
    relations.removeWhere((_, relation) => relation.userId == userId);
    episodes.removeWhere((episode) => episode.userId == userId);
  }
}

/// 固定输出的 [LlmClient]：根据 system prompt 区分抽取 / 摘要 / 标题调用。
class FakeLlmClient implements LlmClient {
  FakeLlmClient({
    this.extractionJson = defaultExtraction,
    this.summary = '这是一段合并后的中文摘要',
    this.title = '测试标题',
    this.throwOnComplete = false,
  });

  static const String defaultExtraction =
      '{"memories":[],"entities":[],"relations":[]}';

  String extractionJson;
  String summary;
  String title;
  bool throwOnComplete;

  int extractionCalls = 0;
  int summaryCalls = 0;
  int titleCalls = 0;
  final List<String> systemPrompts = <String>[];
  final List<String> userPrompts = <String>[];
  final List<String?> models = <String?>[];

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.2,
    int maxTokens = 1200,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    systemPrompts.add(systemPrompt);
    userPrompts.add(userPrompt);
    models.add(model);
    if (throwOnComplete) {
      throw StateError('fake llm failure');
    }
    if (systemPrompt.contains('记忆抽取器')) {
      extractionCalls++;
      return extractionJson;
    }
    if (systemPrompt.contains('对话压缩器')) {
      summaryCalls++;
      return summary;
    }
    titleCalls++;
    return title;
  }
}
