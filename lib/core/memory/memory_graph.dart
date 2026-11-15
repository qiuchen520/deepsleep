/// 记忆知识网（纯 Dart）：
/// - 实体归一化（大小写 / 空白 / 别名合并）与实体、关系写入去重；
/// - 查询侧的实体扩展（命中实体 + 1 跳邻居），供检索打分使用；
/// - 可视化快照构建（按 mentionCount / 关系权重取前 maxNodes，
///   边只保留两端都在节点集合中的）。
library;

import '../../data/models/memory_models.dart';
import '../utils/ids.dart';
import 'extraction.dart';
import 'memory_utils.dart';

/// 一次图更新的结果：需要写入存储的实体与关系（均为增量更新后的完整行）。
class GraphUpdate {
  const GraphUpdate({
    this.entities = const <MemoryEntity>[],
    this.relations = const <MemoryRelation>[],
  });

  final List<MemoryEntity> entities;
  final List<MemoryRelation> relations;
}

/// 把抽取结果合并进已有实体 / 关系，产出需要保存的行。
///
/// - 实体按 [normalizeEntityKey] 归一化后合并，别名去重，mentionCount 累加；
/// - 关系按「source + relation + target」三元组去重，重复时权重累加。
GraphUpdate buildGraphUpdate({
  required String userId,
  required List<MemoryEntity> existingEntities,
  required List<MemoryRelation> existingRelations,
  required ParsedExtraction extraction,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();

  // 已有实体索引：实体名 + 别名都映射到同一个实体。
  final existingByKey = <String, MemoryEntity>{};
  for (final entity in existingEntities) {
    final key = normalizeEntityKey(entity.name);
    if (key.isNotEmpty) existingByKey.putIfAbsent(key, () => entity);
    for (final alias in entity.aliases) {
      final aliasKey = normalizeEntityKey(alias);
      if (aliasKey.isNotEmpty) existingByKey.putIfAbsent(aliasKey, () => entity);
    }
  }

  final accumulators = <String, _EntityAccumulator>{};

  void mention(String rawName, {String? type}) {
    final display = normalizeEntityName(rawName);
    if (display.isEmpty) return;
    final key = normalizeEntityKey(display);
    if (key.isEmpty) return;
    final accumulator = accumulators.putIfAbsent(
      key,
      () => _EntityAccumulator(name: display, type: type ?? 'concept'),
    );
    if (type != null && type.trim().isNotEmpty) {
      accumulator.type = type.trim();
    }
    accumulator.mentions++;
    accumulator.variants.add(display);
  }

  for (final entity in extraction.entities) {
    mention(entity.name, type: entity.type);
  }
  for (final relation in extraction.relations) {
    mention(relation.source);
    mention(relation.target);
  }
  for (final memory in extraction.memories) {
    for (final entity in memory.entities) {
      mention(entity);
    }
    if ((memory.subject ?? '').trim().isNotEmpty) mention(memory.subject!);
    if ((memory.object ?? '').trim().isNotEmpty) mention(memory.object!);
    for (final keyword in memory.keywords) {
      final trimmed = keyword.trim();
      // 关键词里的大写专名（如 Dart、DeepSeek）也当作实体候选。
      if (trimmed.isNotEmpty && trimmed != trimmed.toLowerCase()) {
        mention(trimmed);
      }
    }
  }

  final entitiesToSave = <MemoryEntity>[];
  for (final entry in accumulators.entries) {
    final accumulator = entry.value;
    final existing = existingByKey[entry.key];
    if (existing != null) {
      final aliases = <String>{...existing.aliases};
      final existingKey = normalizeEntityKey(existing.name);
      for (final variant in accumulator.variants) {
        final variantKey = normalizeEntityKey(variant);
        if (variantKey != existingKey &&
            !aliases.any((alias) => normalizeEntityKey(alias) == variantKey)) {
          aliases.add(variant);
        }
      }
      entitiesToSave.add(
        MemoryEntity(
          id: existing.id,
          userId: userId,
          name: existing.name,
          type: existing.type.trim().isEmpty ? accumulator.type : existing.type,
          aliases: aliases.toList()..sort(),
          mentionCount: existing.mentionCount + accumulator.mentions,
          firstSeenAt: existing.firstSeenAt,
          lastSeenAt: timestamp,
        ),
      );
    } else {
      entitiesToSave.add(
        MemoryEntity(
          id: Ids.newId('ent'),
          userId: userId,
          name: accumulator.name,
          type: accumulator.type,
          aliases: const <String>[],
          mentionCount: accumulator.mentions,
          firstSeenAt: timestamp,
          lastSeenAt: timestamp,
        ),
      );
    }
  }

  // 关系：抽取结果 + 记忆三元组。
  final relationTriples = <_Triple>[];
  for (final relation in extraction.relations) {
    relationTriples.add(
      _Triple(
        source: relation.source,
        relation: relation.relation,
        target: relation.target,
      ),
    );
  }
  for (final memory in extraction.memories) {
    final subject = memory.subject?.trim() ?? '';
    final predicate = memory.predicate?.trim() ?? '';
    final object = memory.object?.trim() ?? '';
    if (subject.isEmpty || predicate.isEmpty || object.isEmpty) continue;
    relationTriples.add(
      _Triple(source: subject, relation: predicate, target: object),
    );
  }

  final existingRelationsByKey = <String, MemoryRelation>{};
  for (final relation in existingRelations) {
    final key = _relationKey(
      relation.sourceName,
      relation.relation,
      relation.targetName,
    );
    if (key.isNotEmpty) existingRelationsByKey.putIfAbsent(key, () => relation);
  }

  final relationsToSave = <String, MemoryRelation>{};
  for (final triple in relationTriples) {
    final key = _relationKey(triple.source, triple.relation, triple.target);
    if (key.isEmpty) continue;
    final existing =
        existingRelationsByKey[key] ?? relationsToSave[key];
    if (existing != null) {
      relationsToSave[key] = MemoryRelation(
        id: existing.id,
        userId: userId,
        sourceName: existing.sourceName,
        relation: existing.relation,
        targetName: existing.targetName,
        weight: existing.weight + 1.0,
        updatedAt: timestamp,
        memoryId: existing.memoryId,
      );
    } else {
      relationsToSave[key] = MemoryRelation(
        id: Ids.newId('rel'),
        userId: userId,
        sourceName: normalizeEntityName(triple.source),
        relation: triple.relation.trim(),
        targetName: normalizeEntityName(triple.target),
        weight: 1.0,
        updatedAt: timestamp,
      );
    }
  }

  return GraphUpdate(
    entities: entitiesToSave,
    relations: relationsToSave.values.toList(),
  );
}

/// 查询侧图扩展：找出查询命中的实体，并沿关系走 [maxHops] 跳，返回归一化 key 集合。
Set<String> expandQueryEntities({
  required String query,
  required Set<String> queryTokens,
  required List<MemoryEntity> entities,
  required List<MemoryRelation> relations,
  int maxHops = 1,
}) {
  final queryLower = query.toLowerCase();
  final seeds = <String>{};
  for (final entity in entities) {
    final key = normalizeEntityKey(entity.name);
    if (key.isEmpty) continue;
    final names = <String>[entity.name, ...entity.aliases];
    var hit = queryLower.contains(key) ||
        names.any((name) => queryLower.contains(name.toLowerCase()));
    if (!hit) {
      for (final token in queryTokens) {
        if (tokenMatchesKey(key, token)) {
          hit = true;
          break;
        }
        for (final name in names) {
          final nameKey = normalizeEntityKey(name);
          if (nameKey.isNotEmpty && tokenMatchesKey(nameKey, token)) {
            hit = true;
            break;
          }
        }
        if (hit) break;
      }
    }
    if (hit) seeds.add(key);
  }
  if (seeds.isEmpty) return const <String>{};

  final expanded = <String>{...seeds};
  var frontier = <String>{...seeds};
  for (var hop = 0; hop < maxHops; hop++) {
    final next = <String>{};
    for (final relation in relations) {
      final source = normalizeEntityKey(relation.sourceName);
      final target = normalizeEntityKey(relation.targetName);
      if (source.isEmpty || target.isEmpty) continue;
      if (frontier.contains(source)) next.add(target);
      if (frontier.contains(target)) next.add(source);
    }
    next.removeAll(expanded);
    if (next.isEmpty) break;
    expanded.addAll(next);
    frontier = next;
  }
  return expanded;
}

/// 构建可视化快照。
///
/// 节点按 mentionCount、关系度数与权重排序取前 [maxNodes]；
/// 边只保留两端都在节点集合中的；记忆按重要度、更新时间取前 [maxNodes] 条 active。
MemoryGraphSnapshot buildGraphSnapshot({
  required List<MemoryItem> memories,
  required List<MemoryEntity> entities,
  required List<MemoryRelation> relations,
  int maxNodes = 60,
}) {
  if (maxNodes <= 0) return const MemoryGraphSnapshot();

  final degree = <String, double>{};
  final weightSum = <String, double>{};
  for (final relation in relations) {
    final source = normalizeEntityKey(relation.sourceName);
    final target = normalizeEntityKey(relation.targetName);
    if (source.isEmpty || target.isEmpty) continue;
    degree[source] = (degree[source] ?? 0) + 1;
    degree[target] = (degree[target] ?? 0) + 1;
    weightSum[source] = (weightSum[source] ?? 0) + relation.weight;
    weightSum[target] = (weightSum[target] ?? 0) + relation.weight;
  }

  double entityWeight(MemoryEntity entity) {
    final key = normalizeEntityKey(entity.name);
    return (degree[key] ?? 0) * 10 + (weightSum[key] ?? 0);
  }

  final sortedEntities = <MemoryEntity>[...entities];
  sortedEntities.sort((a, b) {
    final byMention = b.mentionCount.compareTo(a.mentionCount);
    if (byMention != 0) return byMention;
    final byWeight = entityWeight(b).compareTo(entityWeight(a));
    if (byWeight != 0) return byWeight;
    return a.name.compareTo(b.name);
  });
  final selectedEntities = sortedEntities.take(maxNodes).toList();
  final nodeKeys = <String>{
    for (final entity in selectedEntities) normalizeEntityKey(entity.name),
  }..removeWhere((key) => key.isEmpty);

  final selectedRelations = <MemoryRelation>[
    for (final relation in relations)
      if (nodeKeys.contains(normalizeEntityKey(relation.sourceName)) &&
          nodeKeys.contains(normalizeEntityKey(relation.targetName)))
        relation,
  ];
  selectedRelations.sort((a, b) {
    final byWeight = b.weight.compareTo(a.weight);
    if (byWeight != 0) return byWeight;
    return a.id.compareTo(b.id);
  });

  final activeMemories = <MemoryItem>[
    for (final memory in memories)
      if (memory.status == MemoryStatus.active) memory,
  ];
  activeMemories.sort((a, b) {
    final byImportance = b.importance.compareTo(a.importance);
    if (byImportance != 0) return byImportance;
    return b.updatedAt.compareTo(a.updatedAt);
  });

  return MemoryGraphSnapshot(
    entities: selectedEntities,
    relations: selectedRelations,
    memories: activeMemories.take(maxNodes).toList(),
  );
}

class _EntityAccumulator {
  _EntityAccumulator({required this.name, required this.type});

  final String name;
  String type;
  int mentions = 0;
  final Set<String> variants = <String>{};
}

class _Triple {
  const _Triple({
    required this.source,
    required this.relation,
    required this.target,
  });

  final String source;
  final String relation;
  final String target;
}

String _relationKey(String source, String relation, String target) {
  final sourceKey = normalizeEntityKey(source);
  final relationKey = normalizeEntityKey(relation);
  final targetKey = normalizeEntityKey(target);
  if (sourceKey.isEmpty || targetKey.isEmpty) return '';
  return '$sourceKey|$relationKey|$targetKey';
}
