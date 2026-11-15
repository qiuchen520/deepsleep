/// [MemoryStore] 的 SQLite 实现。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/memory/contracts.dart';
import '../models/memory_models.dart';
import 'app_database.dart';

class SqliteMemoryStore implements MemoryStore {
  SqliteMemoryStore(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  @override
  Future<void> init() async {
    // 表结构由 AppDatabase 统一创建，这里只需确保实例可用。
    await _db.rawQuery('SELECT 1');
  }

  @override
  Future<List<MemoryItem>> listMemories({
    required String userId,
    MemoryStatus? status,
    int limit = 500,
    int offset = 0,
  }) async {
    final rows = await _db.query(
      'memories',
      where: status == null ? 'user_id = ?' : 'user_id = ? AND status = ?',
      whereArgs: status == null ? [userId] : [userId, status.name],
      orderBy: 'importance DESC, updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows
        .map((r) => MemoryItem.fromJson(_decode(r['payload'])))
        .toList();
  }

  @override
  Future<MemoryItem?> getMemory(String id) async {
    final rows = await _db.query(
      'memories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryItem.fromJson(_decode(rows.first['payload']));
  }

  @override
  Future<void> saveMemory(MemoryItem item) async {
    await saveMemories(<MemoryItem>[item]);
  }

  @override
  Future<void> saveMemories(List<MemoryItem> items) async {
    if (items.isEmpty) return;
    final batch = _db.batch();
    for (final item in items) {
      batch.insert(
        'memories',
        <String, Object?>{
          'id': item.id,
          'user_id': item.userId,
          'kind': item.kind.name,
          'status': item.status.name,
          'importance': item.importance,
          'updated_at': item.updatedAt.millisecondsSinceEpoch,
          'payload': jsonEncode(item.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> deleteMemory(String id) async {
    await _db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markAccessed(List<String> ids, DateTime at) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    final rows = await _db.query(
      'memories',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final batch = _db.batch();
    for (final row in rows) {
      final item = MemoryItem.fromJson(_decode(row['payload']));
      batch.update(
        'memories',
        <String, Object?>{
          'payload': jsonEncode(
            item
                .copyWith(
                  lastAccessAt: at,
                  accessCount: item.accessCount + 1,
                )
                .toJson(),
          ),
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<MemoryEntity>> listEntities({
    required String userId,
    int limit = 500,
  }) async {
    final rows = await _db.query(
      'entities',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'mention_count DESC, last_seen_at DESC',
      limit: limit,
    );
    return rows
        .map((r) => MemoryEntity.fromJson(_decode(r['payload'])))
        .toList();
  }

  @override
  Future<void> saveEntities(List<MemoryEntity> entities) async {
    if (entities.isEmpty) return;
    final batch = _db.batch();
    for (final entity in entities) {
      batch.insert(
        'entities',
        <String, Object?>{
          'id': entity.id,
          'user_id': entity.userId,
          'name': entity.name,
          'name_lower': entity.name.toLowerCase(),
          'mention_count': entity.mentionCount,
          'last_seen_at': entity.lastSeenAt.millisecondsSinceEpoch,
          'payload': jsonEncode(entity.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<MemoryRelation>> listRelations({
    required String userId,
    int limit = 500,
  }) async {
    final rows = await _db.query(
      'relations',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows
        .map((r) => MemoryRelation.fromJson(_decode(r['payload'])))
        .toList();
  }

  @override
  Future<void> saveRelations(List<MemoryRelation> relations) async {
    if (relations.isEmpty) return;
    final batch = _db.batch();
    for (final relation in relations) {
      batch.insert(
        'relations',
        <String, Object?>{
          'id': relation.id,
          'user_id': relation.userId,
          'source_lower': relation.sourceName.toLowerCase(),
          'target_lower': relation.targetName.toLowerCase(),
          'updated_at': relation.updatedAt.millisecondsSinceEpoch,
          'payload': jsonEncode(relation.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> saveEpisode(Episode episode) async {
    await _db.insert(
      'episodes',
      <String, Object?>{
        'id': episode.id,
        'user_id': episode.userId,
        'session_id': episode.sessionId,
        'created_at': episode.createdAt.millisecondsSinceEpoch,
        'payload': jsonEncode(episode.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<Episode>> listEpisodes({
    required String userId,
    int limit = 50,
  }) async {
    final rows = await _db.query(
      'episodes',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((r) => Episode.fromJson(_decode(r['payload']))).toList();
  }

  @override
  Future<MemoryStats> stats(String userId) async {
    final active = await _count(userId, MemoryStatus.active);
    final superseded = await _count(userId, MemoryStatus.superseded);
    final archived = await _count(userId, MemoryStatus.archived);
    final total = active + superseded + archived;

    final kindRows = await _db.rawQuery(
      'SELECT kind, COUNT(*) AS c FROM memories WHERE user_id = ? AND status = ? GROUP BY kind',
      [userId, MemoryStatus.active.name],
    );
    final byKind = <MemoryKind, int>{};
    for (final row in kindRows) {
      byKind[MemoryKind.fromName(row['kind'] as String?)] =
          (row['c'] as num?)?.toInt() ?? 0;
    }

    final entityCount = await _countTable('entities', userId);
    final relationCount = await _countTable('relations', userId);
    final episodeCount = await _countTable('episodes', userId);

    final latest = await _db.rawQuery(
      'SELECT MAX(updated_at) AS t FROM memories WHERE user_id = ?',
      [userId],
    );
    final latestMs = (latest.first['t'] as num?)?.toInt();

    return MemoryStats(
      total: total,
      active: active,
      superseded: superseded,
      entities: entityCount,
      relations: relationCount,
      episodes: episodeCount,
      byKind: byKind,
      lastUpdatedAt: latestMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(latestMs),
    );
  }

  @override
  Future<void> clearUser(String userId) async {
    for (final table in <String>[
      'memories',
      'entities',
      'relations',
      'episodes',
    ]) {
      await _db.delete(table, where: 'user_id = ?', whereArgs: [userId]);
    }
  }

  Future<int> _count(String userId, MemoryStatus status) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM memories WHERE user_id = ? AND status = ?',
      [userId, status.name],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countTable(String table, String userId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE user_id = ?',
      [userId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> _decode(Object? payload) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is String && payload.isNotEmpty) {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return <String, dynamic>{};
  }
}
