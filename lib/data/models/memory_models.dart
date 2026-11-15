/// 记忆知识网领域模型（纯 Dart）。
library;

import 'dart:math' as math;

/// 记忆类型。参考 RecallOS 的分类方式：事实、偏好、档案、事件、任务、关系。
enum MemoryKind {
  fact('事实'),
  preference('偏好'),
  profile('档案'),
  event('事件'),
  task('任务'),
  relation('关系');

  const MemoryKind(this.label);

  final String label;

  static MemoryKind fromName(String? name) => MemoryKind.values.firstWhere(
        (e) => e.name == name,
        orElse: () => MemoryKind.fact,
      );
}

enum MemoryStatus {
  active,
  superseded,
  archived;

  static MemoryStatus fromName(String? name) =>
      MemoryStatus.values.firstWhere(
        (e) => e.name == name,
        orElse: () => MemoryStatus.active,
      );
}

/// 一条记忆（知识网络中的「节点文本 + 元信息」）。
class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.userId,
    required this.kind,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.keywords = const <String>[],
    this.entities = const <String>[],
    this.importance = 0.5,
    this.confidence = 0.8,
    this.status = MemoryStatus.active,
    this.supersededBy,
    this.sourceSessionId,
    this.sourceMessageId,
    this.subject,
    this.predicate,
    this.object,
    this.fingerprint = '',
    this.lastAccessAt,
    this.accessCount = 0,
    this.pinned = false,
  });

  final String id;
  final String userId;
  final MemoryKind kind;

  /// 自然语言表述，例如「用户偏好用 Dart 写客户端」。
  final String content;

  /// 检索用关键词（小写）。
  final List<String> keywords;

  /// 涉及实体名称（用于知识图扩展召回）。
  final List<String> entities;

  /// 重要度 0~1，手动置顶/用户档案通常更高。
  final double importance;

  /// 置信度 0~1，来自抽取模型。
  final double confidence;

  final MemoryStatus status;
  final String? supersededBy;
  final String? sourceSessionId;
  final String? sourceMessageId;

  /// 结构化三元组（可选）：主语-谓语-宾语，用于冲突检测。
  final String? subject;
  final String? predicate;
  final String? object;

  final String fingerprint;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessAt;
  final int accessCount;
  final bool pinned;

  /// 空闲衰减后的「新鲜度」0~1，由评分器计算，不落库。
  double freshness({DateTime? now}) {
    final n = now ?? DateTime.now();
    final days = n.difference(updatedAt).inMinutes / (60 * 24);
    if (days <= 0) return 1.0;
    // 半衰期 21 天：越久越淡忘，但保留底噪。
    return 0.15 + 0.85 * math.pow(0.5, days / 21).toDouble();
  }

  MemoryItem copyWith({
    MemoryKind? kind,
    String? content,
    List<String>? keywords,
    List<String>? entities,
    double? importance,
    double? confidence,
    MemoryStatus? status,
    String? supersededBy,
    String? subject,
    String? predicate,
    String? object,
    String? fingerprint,
    DateTime? updatedAt,
    DateTime? lastAccessAt,
    int? accessCount,
    bool? pinned,
  }) {
    return MemoryItem(
      id: id,
      userId: userId,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      keywords: keywords ?? this.keywords,
      entities: entities ?? this.entities,
      importance: importance ?? this.importance,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      supersededBy: supersededBy ?? this.supersededBy,
      sourceSessionId: sourceSessionId,
      sourceMessageId: sourceMessageId,
      subject: subject ?? this.subject,
      predicate: predicate ?? this.predicate,
      object: object ?? this.object,
      fingerprint: fingerprint ?? this.fingerprint,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessAt: lastAccessAt ?? this.lastAccessAt,
      accessCount: accessCount ?? this.accessCount,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'userId': userId,
        'kind': kind.name,
        'content': content,
        'keywords': keywords,
        'entities': entities,
        'importance': importance,
        'confidence': confidence,
        'status': status.name,
        'supersededBy': supersededBy,
        'sourceSessionId': sourceSessionId,
        'sourceMessageId': sourceMessageId,
        'subject': subject,
        'predicate': predicate,
        'object': object,
        'fingerprint': fingerprint,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastAccessAt': lastAccessAt?.toIso8601String(),
        'accessCount': accessCount,
        'pinned': pinned,
      };

  static MemoryItem fromJson(Map<String, dynamic> json) => MemoryItem(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? 'default',
        kind: MemoryKind.fromName(json['kind'] as String?),
        content: json['content'] as String? ?? '',
        keywords: (json['keywords'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        entities: (json['entities'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
        status: MemoryStatus.fromName(json['status'] as String?),
        supersededBy: json['supersededBy'] as String?,
        sourceSessionId: json['sourceSessionId'] as String?,
        sourceMessageId: json['sourceMessageId'] as String?,
        subject: json['subject'] as String?,
        predicate: json['predicate'] as String?,
        object: json['object'] as String?,
        fingerprint: json['fingerprint'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
                DateTime.now(),
        lastAccessAt: DateTime.tryParse(json['lastAccessAt'] as String? ?? ''),
        accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
        pinned: json['pinned'] as bool? ?? false,
      );
}

/// 知识网络中的实体（人、项目、技术、地点……）。
class MemoryEntity {
  const MemoryEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.aliases = const <String>[],
    this.mentionCount = 1,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  final String id;
  final String userId;
  final String name;
  final String type;
  final List<String> aliases;
  final int mentionCount;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'userId': userId,
        'name': name,
        'type': type,
        'aliases': aliases,
        'mentionCount': mentionCount,
        'firstSeenAt': firstSeenAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
      };

  static MemoryEntity fromJson(Map<String, dynamic> json) => MemoryEntity(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? 'default',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'concept',
        aliases: (json['aliases'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        mentionCount: (json['mentionCount'] as num?)?.toInt() ?? 1,
        firstSeenAt:
            DateTime.tryParse(json['firstSeenAt'] as String? ?? '') ??
                DateTime.now(),
        lastSeenAt:
            DateTime.tryParse(json['lastSeenAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// 实体之间的关系（知识图的边）。
class MemoryRelation {
  const MemoryRelation({
    required this.id,
    required this.userId,
    required this.sourceName,
    required this.relation,
    required this.targetName,
    required this.updatedAt,
    this.weight = 1.0,
    this.memoryId,
  });

  final String id;
  final String userId;
  final String sourceName;
  final String relation;
  final String targetName;
  final double weight;
  final DateTime updatedAt;
  final String? memoryId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'userId': userId,
        'sourceName': sourceName,
        'relation': relation,
        'targetName': targetName,
        'weight': weight,
        'updatedAt': updatedAt.toIso8601String(),
        'memoryId': memoryId,
      };

  static MemoryRelation fromJson(Map<String, dynamic> json) => MemoryRelation(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? 'default',
        sourceName: json['sourceName'] as String? ?? '',
        relation: json['relation'] as String? ?? 'RELATED_TO',
        targetName: json['targetName'] as String? ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
                DateTime.now(),
        memoryId: json['memoryId'] as String?,
      );
}

/// 原始对话片段（逐字留存，供向量/关键词召回兜底）。
class Episode {
  const Episode({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.content,
    required this.createdAt,
    this.summary = '',
    this.tokens = 0,
  });

  final String id;
  final String userId;
  final String sessionId;
  final String content;
  final String summary;
  final int tokens;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'userId': userId,
        'sessionId': sessionId,
        'content': content,
        'summary': summary,
        'tokens': tokens,
        'createdAt': createdAt.toIso8601String(),
      };

  static Episode fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? 'default',
        sessionId: json['sessionId'] as String? ?? '',
        content: json['content'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        tokens: (json['tokens'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// 记忆统计。
class MemoryStats {
  const MemoryStats({
    this.total = 0,
    this.active = 0,
    this.superseded = 0,
    this.entities = 0,
    this.relations = 0,
    this.episodes = 0,
    this.byKind = const <MemoryKind, int>{},
    this.lastUpdatedAt,
  });

  final int total;
  final int active;
  final int superseded;
  final int entities;
  final int relations;
  final int episodes;
  final Map<MemoryKind, int> byKind;
  final DateTime? lastUpdatedAt;
}
