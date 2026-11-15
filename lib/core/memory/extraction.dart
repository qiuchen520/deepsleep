/// 记忆抽取结果的解析与合并决策（纯 Dart）。
///
/// 职责：
/// 1. 把模型输出的（可能带围栏 / 前后废话的）JSON 解析成 [ParsedExtraction]；
///    单条失败只记录错误、不中断整体解析（容错）。
/// 2. 把抽取结果与已有记忆对比：指纹 / 相似度去重（阈值默认 0.86 -> 更新），
///    `subject + predicate` 相同但 `object` 不同视为冲突 -> 旧记忆置为 superseded；
///    最终产出可直接落库的 [MemoryItem] 列表。
library;

import 'dart:math' as math;

import '../../data/models/memory_models.dart';
import '../utils/ids.dart';
import 'memory_utils.dart';

/// 抽取模型建议的动作。
enum MemoryAction {
  add,
  update,
  supersede;

  static MemoryAction fromName(String? name) {
    switch (name?.trim().toLowerCase()) {
      case 'update':
      case 'merge':
      case 'append':
        return MemoryAction.update;
      case 'supersede':
      case 'replace':
      case 'delete':
        return MemoryAction.supersede;
      default:
        return MemoryAction.add;
    }
  }
}

/// 单条解析后的记忆（模型给的数据，尚未落库）。
class ParsedMemory {
  const ParsedMemory({
    required this.kind,
    required this.content,
    this.keywords = const <String>[],
    this.entities = const <String>[],
    this.importance = 0.5,
    this.confidence = 0.8,
    this.subject,
    this.predicate,
    this.object,
    this.action = MemoryAction.add,
  });

  final MemoryKind kind;
  final String content;
  final List<String> keywords;
  final List<String> entities;
  final double importance;
  final double confidence;
  final String? subject;
  final String? predicate;
  final String? object;
  final MemoryAction action;
}

/// 解析后的实体。
class ParsedEntity {
  const ParsedEntity({required this.name, this.type = 'concept'});

  final String name;
  final String type;
}

/// 解析后的关系（知识图的边）。
class ParsedRelation {
  const ParsedRelation({
    required this.source,
    required this.relation,
    required this.target,
  });

  final String source;
  final String relation;
  final String target;
}

/// 一次抽取的完整解析结果。
class ParsedExtraction {
  const ParsedExtraction({
    this.memories = const <ParsedMemory>[],
    this.entities = const <ParsedEntity>[],
    this.relations = const <ParsedRelation>[],
    this.errors = const <String>[],
  });

  final List<ParsedMemory> memories;
  final List<ParsedEntity> entities;
  final List<ParsedRelation> relations;

  /// 解析过程中被跳过的条目说明（不影响整体成功）。
  final List<String> errors;

  bool get isEmpty => memories.isEmpty && entities.isEmpty && relations.isEmpty;

  /// 容错解析模型输出。
  ///
  /// 支持：```json 围栏 / 前后解释文字 / 顶层对象包 `memories`、`entities`、
  /// `relations` / 顶层直接是数组 / 单个记忆对象 / 尾逗号。
  /// 单条记忆缺少 content 等情况只记录 [errors]，其它条目照常解析。
  factory ParsedExtraction.parse(String raw) {
    final errors = <String>[];
    final memories = <ParsedMemory>[];
    final entities = <ParsedEntity>[];
    final relations = <ParsedRelation>[];

    final decoded = decodeJsonLoosely(raw);
    if (decoded == null) {
      errors.add('模型输出不是有效 JSON，已忽略');
      return ParsedExtraction(errors: errors);
    }

    late final List<dynamic> memoryRaw;
    late final List<dynamic> entityRaw;
    late final List<dynamic> relationRaw;

    if (decoded is List) {
      memoryRaw = decoded;
      entityRaw = const <dynamic>[];
      relationRaw = const <dynamic>[];
    } else if (decoded is Map) {
      final map = _asMap(decoded);
      if (map.containsKey('content') &&
          !map.containsKey('memories') &&
          !map.containsKey('items')) {
        // 模型直接返回了单条记忆对象。
        memoryRaw = <dynamic>[map];
      } else {
        memoryRaw = jsonList(
          map['memories'] ?? map['memory'] ?? map['items'] ?? map['results'],
        );
      }
      entityRaw = jsonList(map['entities'] ?? map['entity']);
      relationRaw = jsonList(map['relations'] ?? map['relation'] ?? map['edges']);
    } else {
      errors.add('模型输出 JSON 顶层类型不支持，已忽略');
      return ParsedExtraction(errors: errors);
    }

    for (var i = 0; i < memoryRaw.length; i++) {
      final parsed = _parseMemory(memoryRaw[i], i, errors);
      if (parsed != null) memories.add(parsed);
    }
    for (var i = 0; i < entityRaw.length; i++) {
      final parsed = _parseEntity(entityRaw[i], i, errors);
      if (parsed != null) entities.add(parsed);
    }
    for (var i = 0; i < relationRaw.length; i++) {
      final parsed = _parseRelation(relationRaw[i], i, errors);
      if (parsed != null) relations.add(parsed);
    }

    return ParsedExtraction(
      memories: memories,
      entities: entities,
      relations: relations,
      errors: errors,
    );
  }
}

/// 合并决策结果。
class MergeDecision {
  const MergeDecision({
    this.toSave = const <MemoryItem>[],
    this.touched = const <MemoryItem>[],
    this.added = 0,
    this.updated = 0,
    this.superseded = 0,
    this.skipped = 0,
    this.entityNames = const <String>[],
  });

  /// 本次需要写入存储的全部记忆（含状态为 superseded 的旧记忆）。
  final List<MemoryItem> toSave;

  /// 本次新增 / 更新且仍为 active 的记忆（用于 UI 展示）。
  final List<MemoryItem> touched;

  final int added;
  final int updated;
  final int superseded;
  final int skipped;
  final List<String> entityNames;
}

/// 根据抽取结果与已有记忆生成合并决策。
///
/// 规则：
/// - 内容指纹相同或相似度 `>= [duplicateThreshold]`：视为重复 -> 更新已有记忆；
/// - 同一 `subject + predicate` 但 `object` 不同：旧记忆置为 superseded，
///   并写入 `supersededBy` 指向新记忆；
/// - 模型 `action == supersede` 时同样优先取代匹配到的旧记忆；
/// - 其余情况新增；同一批抽取里重复内容只保留第一条。
MergeDecision buildMergeDecision({
  required String userId,
  required ParsedExtraction extraction,
  required List<MemoryItem> existingMemories,
  DateTime? now,
  String? sessionId,
  String? messageId,
  double duplicateThreshold = 0.86,
}) {
  final timestamp = now ?? DateTime.now();
  final existingIds = existingMemories.map((item) => item.id).toSet();
  final candidates = <MemoryItem>[
    ...existingMemories.where((item) => item.status == MemoryStatus.active),
  ];
  // 本轮最终要写入的记忆（新增 / 更新）。
  final pending = <String, MemoryItem>{};
  // 已有记忆被取代后的版本。
  final supersededItems = <String, MemoryItem>{};
  final touchedIds = <String>{};
  final seenFingerprints = <String, String>{};
  final entityNames = <String>{};

  var added = 0;
  var updated = 0;
  var supersededCount = 0;
  var skipped = 0;

  void markSuperseded(MemoryItem old, String newId) {
    final oldVersion = old.copyWith(
      status: MemoryStatus.superseded,
      supersededBy: newId,
      updatedAt: timestamp,
    );
    pending.remove(old.id);
    if (existingIds.contains(old.id)) {
      supersededItems[old.id] = oldVersion;
    }
    candidates.removeWhere((candidate) => candidate.id == old.id);
    touchedIds.remove(old.id);
  }

  for (final parsed in extraction.memories) {
    final content = parsed.content.trim();
    if (content.isEmpty) {
      skipped++;
      continue;
    }
    final fingerprint = Ids.fingerprint(content);
    if (seenFingerprints.containsKey(fingerprint)) {
      skipped++;
      continue;
    }

    final keywords = <String>{
      for (final keyword in parsed.keywords)
        if (keyword.trim().isNotEmpty) keyword.trim().toLowerCase(),
    };
    if (keywords.isEmpty) {
      keywords.addAll(extractKeywords(content));
    }
    final entities = <String>{
      for (final entity in parsed.entities)
        if (entity.trim().isNotEmpty) entity.trim(),
    };
    entityNames.addAll(entities);
    final importance = clamp01(parsed.importance);

    // 1) 指纹 / 相似度匹配已有记忆。
    MemoryItem? match;
    var bestSimilarity = 0.0;
    for (final candidate in candidates) {
      final candidateFingerprint = candidate.fingerprint.isNotEmpty
          ? candidate.fingerprint
          : Ids.fingerprint(candidate.content);
      if (candidateFingerprint == fingerprint) {
        match = candidate;
        bestSimilarity = 1.0;
        break;
      }
    }
    if (match == null) {
      for (final candidate in candidates) {
        final similarity = textSimilarity(candidate.content, content);
        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          match = candidate;
        }
      }
    }

    // 2) 结构化三元组冲突检测。
    final subjectKey = _keyOrNull(parsed.subject);
    final predicateKey = _keyOrNull(parsed.predicate);
    final objectKey = _keyOrNull(parsed.object);
    MemoryItem? conflict;
    if (subjectKey != null && predicateKey != null && objectKey != null) {
      for (final candidate in candidates) {
        final candidateSubject = _keyOrNull(candidate.subject);
        final candidatePredicate = _keyOrNull(candidate.predicate);
        final candidateObject = _keyOrNull(candidate.object);
        if (candidateSubject == subjectKey &&
            candidatePredicate == predicateKey &&
            candidateObject != null &&
            candidateObject != objectKey) {
          conflict = candidate;
          break;
        }
      }
    }

    final matched = match;
    final shouldSupersede =
        parsed.action == MemoryAction.supersede || conflict != null;

    if (shouldSupersede && (conflict != null || matched != null)) {
      final old = conflict ?? matched!;
      final newItem = _buildNewItem(
        userId: userId,
        parsed: parsed,
        content: content,
        keywords: keywords,
        entities: entities,
        importance: importance,
        fingerprint: fingerprint,
        timestamp: timestamp,
        sessionId: sessionId,
        messageId: messageId,
      );
      markSuperseded(old, newItem.id);
      if (existingIds.contains(old.id)) supersededCount++;
      pending[newItem.id] = newItem;
      candidates.add(newItem);
      added++;
      touchedIds.add(newItem.id);
      seenFingerprints[fingerprint] = newItem.id;
      continue;
    }

    if (matched != null &&
        (bestSimilarity >= duplicateThreshold ||
            matched.fingerprint == fingerprint ||
            parsed.action == MemoryAction.update)) {
      final target = matched;
      final parsedSubject = _emptyToNull(parsed.subject);
      final parsedPredicate = _emptyToNull(parsed.predicate);
      final parsedObject = _emptyToNull(parsed.object);
      final updatedItem = target.copyWith(
        kind: parsed.kind,
        content: content,
        keywords: _mergeUnique(target.keywords, keywords),
        entities: _mergeUnique(target.entities, entities),
        importance: math.max(target.importance, importance),
        confidence: math.max(target.confidence, clamp01(parsed.confidence)),
        status: MemoryStatus.active,
        subject: parsedSubject ?? target.subject,
        predicate: parsedPredicate ?? target.predicate,
        object: parsedObject ?? target.object,
        fingerprint: fingerprint,
        updatedAt: timestamp,
      );
      pending[target.id] = updatedItem;
      candidates.removeWhere((candidate) => candidate.id == target.id);
      candidates.add(updatedItem);
      updated++;
      touchedIds.add(target.id);
      seenFingerprints[fingerprint] = target.id;
      continue;
    }

    // 3) 全新记忆。
    final newItem = _buildNewItem(
      userId: userId,
      parsed: parsed,
      content: content,
      keywords: keywords,
      entities: entities,
      importance: importance,
      fingerprint: fingerprint,
      timestamp: timestamp,
      sessionId: sessionId,
      messageId: messageId,
    );
    pending[newItem.id] = newItem;
    candidates.add(newItem);
    added++;
    touchedIds.add(newItem.id);
    seenFingerprints[fingerprint] = newItem.id;
  }

  final toSave = <MemoryItem>[
    ...supersededItems.values,
    ...pending.values,
  ];
  final touched = <MemoryItem>[
    for (final item in pending.values)
      if (touchedIds.contains(item.id) &&
          item.status == MemoryStatus.active)
        item,
  ];

  return MergeDecision(
    toSave: toSave,
    touched: touched,
    added: added,
    updated: updated,
    superseded: supersededCount,
    skipped: skipped,
    entityNames: entityNames.toList()..sort(),
  );
}

/// 抽取模型给某类记忆的默认重要度。
double defaultImportanceFor(MemoryKind kind) => switch (kind) {
      MemoryKind.profile => 0.85,
      MemoryKind.preference => 0.7,
      MemoryKind.task => 0.65,
      MemoryKind.fact => 0.6,
      MemoryKind.relation => 0.55,
      MemoryKind.event => 0.5,
    };

MemoryItem _buildNewItem({
  required String userId,
  required ParsedMemory parsed,
  required String content,
  required Set<String> keywords,
  required Set<String> entities,
  required double importance,
  required String fingerprint,
  required DateTime timestamp,
  String? sessionId,
  String? messageId,
}) {
  return MemoryItem(
    id: Ids.newId('mem'),
    userId: userId,
    kind: parsed.kind,
    content: content,
    keywords: keywords.toList()..sort(),
    entities: entities.toList()..sort(),
    importance: importance,
    confidence: clamp01(parsed.confidence),
    status: MemoryStatus.active,
    sourceSessionId: sessionId,
    sourceMessageId: messageId,
    subject: _emptyToNull(parsed.subject),
    predicate: _emptyToNull(parsed.predicate),
    object: _emptyToNull(parsed.object),
    fingerprint: fingerprint,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

ParsedMemory? _parseMemory(dynamic raw, int index, List<String> errors) {
  final map = _asMap(raw);
  if (map.isEmpty) {
    errors.add('第 ${index + 1} 条记忆格式无效，已跳过');
    return null;
  }
  final content = jsonString(
    map['content'] ?? map['text'] ?? map['memory'],
  ).trim();
  if (content.isEmpty) {
    errors.add('第 ${index + 1} 条记忆缺少 content，已跳过');
    return null;
  }
  final kind = _parseKind(map['kind'] ?? map['type']);
  final keywords = <String>{};
  for (final keyword in jsonStringList(map['keywords'] ?? map['tags'])) {
    final normalized = keyword.trim().toLowerCase();
    if (normalized.isNotEmpty) keywords.add(normalized);
  }
  final entities = <String>{};
  for (final entity in jsonStringList(map['entities'])) {
    final normalized = entity.trim();
    if (normalized.isNotEmpty) entities.add(normalized);
  }

  final triple = _asMap(map['triple']);
  final subject = jsonString(
    map['subject'] ?? triple['subject'] ?? triple['s'],
  ).trim();
  final predicate = jsonString(
    map['predicate'] ?? triple['predicate'] ?? triple['p'],
  ).trim();
  final object = jsonString(
    map['object'] ?? triple['object'] ?? triple['o'],
  ).trim();

  return ParsedMemory(
    kind: kind,
    content: content,
    keywords: keywords.toList(),
    entities: entities.toList(),
    importance: clamp01(
      jsonDouble(map['importance'], fallback: defaultImportanceFor(kind)),
    ),
    confidence: clamp01(jsonDouble(map['confidence'], fallback: 0.8)),
    subject: _emptyToNull(subject),
    predicate: _emptyToNull(predicate),
    object: _emptyToNull(object),
    action: MemoryAction.fromName(
      jsonString(map['action'] ?? map['op']),
    ),
  );
}

ParsedEntity? _parseEntity(dynamic raw, int index, List<String> errors) {
  if (raw is String) {
    final name = raw.trim();
    if (name.isEmpty) {
      errors.add('第 ${index + 1} 个实体为空，已跳过');
      return null;
    }
    return ParsedEntity(name: name);
  }
  final map = _asMap(raw);
  final name = jsonString(map['name'] ?? map['entity']).trim();
  if (name.isEmpty) {
    errors.add('第 ${index + 1} 个实体缺少 name，已跳过');
    return null;
  }
  final type = jsonString(
    map['type'] ?? map['category'],
    fallback: 'concept',
  ).trim();
  return ParsedEntity(name: name, type: type.isEmpty ? 'concept' : type);
}

ParsedRelation? _parseRelation(dynamic raw, int index, List<String> errors) {
  final map = _asMap(raw);
  final source = jsonString(map['source'] ?? map['from']).trim();
  final target = jsonString(map['target'] ?? map['to']).trim();
  if (source.isEmpty || target.isEmpty) {
    errors.add('第 ${index + 1} 条关系缺少 source/target，已跳过');
    return null;
  }
  final relation = jsonString(
    map['relation'] ?? map['predicate'] ?? map['type'],
    fallback: 'RELATED_TO',
  ).trim();
  return ParsedRelation(
    source: source,
    relation: relation.isEmpty ? 'RELATED_TO' : relation,
    target: target,
  );
}

MemoryKind _parseKind(dynamic value) {
  final raw = jsonString(value).trim().toLowerCase();
  if (raw.isEmpty) return MemoryKind.fact;
  for (final kind in MemoryKind.values) {
    if (kind.name == raw || kind.label == raw) return kind;
  }
  switch (raw) {
    case 'identity':
    case 'personal':
    case 'user':
    case 'profile':
      return MemoryKind.profile;
    case 'like':
    case 'prefer':
    case 'preference':
      return MemoryKind.preference;
    case 'todo':
    case 'plan':
    case 'intent':
      return MemoryKind.task;
    case 'relationship':
    case 'link':
      return MemoryKind.relation;
    case 'incident':
    case 'history':
      return MemoryKind.event;
    default:
      return MemoryKind.fact;
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, item) => MapEntry(key.toString(), item),
    );
  }
  return const <String, dynamic>{};
}

String? _keyOrNull(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final key = normalizeEntityKey(trimmed);
  return key.isEmpty ? null : key;
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _mergeUnique(Iterable<String> a, Iterable<String> b) {
  final merged = <String>{};
  for (final item in a) {
    final trimmed = item.trim();
    if (trimmed.isNotEmpty) merged.add(trimmed);
  }
  for (final item in b) {
    final trimmed = item.trim();
    if (trimmed.isNotEmpty) merged.add(trimmed);
  }
  return merged.toList()..sort();
}
