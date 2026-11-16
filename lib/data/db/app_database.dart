/// SQLite 持久层：用户档案、会话、消息、记忆知识网。
///
/// 设计取舍：只把需要过滤/排序的字段单独建列，其余内容存 JSON payload。
/// 这样模型演进时不需要频繁写 migration，同时查询仍然走索引。
library;

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/chat_models.dart';
import '../models/memory_models.dart';
import '../models/profile_models.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static AppDatabase? _instance;

  static Future<AppDatabase> instance({String? path}) async {
    if (_instance != null) return _instance!;
    final dbPath = path ?? p.join(await getDatabasesPath(), 'deepsleep.db');
    final database = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
    _instance = AppDatabase._(database);
    await _instance!._ensureDefaultProfile();
    return _instance!;
  }

  /// 测试用：直接注入内存数据库。
  static AppDatabase forTesting(Database database) {
    final db = AppDatabase._(database);
    _instance = db;
    return db;
  }

  Future<void> close() async {
    _instance = null;
    await db.close();
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL,
        title TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_conversations_profile ON conversations(profile_id, archived, pinned, updated_at)',
    );
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_messages_session ON messages(session_id, created_at)',
    );
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        importance REAL NOT NULL DEFAULT 0.5,
        updated_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_memories_user ON memories(user_id, status, updated_at)',
    );
    await db.execute('''
      CREATE TABLE entities (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        name_lower TEXT NOT NULL,
        mention_count INTEGER NOT NULL DEFAULT 1,
        last_seen_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_entities_user ON entities(user_id, name_lower)',
    );
    await db.execute('''
      CREATE TABLE relations (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        source_lower TEXT NOT NULL,
        target_lower TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_relations_user ON relations(user_id, source_lower)',
    );
    await db.execute('''
      CREATE TABLE episodes (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_episodes_user ON episodes(user_id, created_at)',
    );
  }

  Future<void> _ensureDefaultProfile() async {
    final rows = await db.query('profiles', limit: 1);
    if (rows.isNotEmpty) return;
    final now = DateTime.now();
    final profile = UserProfile(
      id: 'default',
      name: '我',
      emoji: '🙂',
      createdAt: now,
      isDefault: true,
    );
    await saveProfile(profile);
  }

  // ---------------------------------------------------------------------------
  // 用户档案
  // ---------------------------------------------------------------------------

  Future<List<UserProfile>> listProfiles() async {
    final rows = await db.query('profiles', orderBy: 'created_at ASC');
    return rows
        .map((r) => UserProfile.fromJson(_decode(r['payload'])))
        .toList();
  }

  Future<UserProfile?> getProfile(String id) async {
    final rows =
        await db.query('profiles', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return UserProfile.fromJson(_decode(rows.first['payload']));
  }

  Future<void> saveProfile(UserProfile profile) async {
    await db.insert(
      'profiles',
      <String, Object?>{
        'id': profile.id,
        'name': profile.name,
        'created_at': profile.createdAt.millisecondsSinceEpoch,
        'payload': jsonEncode(profile.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProfile(String id) async {
    await db.delete('profiles', where: 'id = ?', whereArgs: [id]);
    await db.delete('conversations', where: 'profile_id = ?', whereArgs: [id]);
    await db.delete('memories', where: 'user_id = ?', whereArgs: [id]);
    await db.delete('entities', where: 'user_id = ?', whereArgs: [id]);
    await db.delete('relations', where: 'user_id = ?', whereArgs: [id]);
    await db.delete('episodes', where: 'user_id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // 会话
  // ---------------------------------------------------------------------------

  Future<List<Conversation>> listConversations({String? profileId}) async {
    final rows = await db.query(
      'conversations',
      where: profileId == null
          ? 'archived = 0'
          : 'archived = 0 AND profile_id = ?',
      whereArgs: profileId == null ? null : [profileId],
      orderBy: 'pinned DESC, updated_at DESC',
    );
    return rows
        .map((r) => Conversation.fromJson(_decode(r['payload'])))
        .toList();
  }

  /// 全局搜索：按标题匹配会话。
  Future<List<Conversation>> searchConversations(
    String query, {
    int limit = 50,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return <Conversation>[];
    final rows = await db.query(
      'conversations',
      where: 'title LIKE ?',
      whereArgs: <Object?>['%$q%'],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows
        .map((r) => Conversation.fromJson(_decode(r['payload'])))
        .toList();
  }

  /// 全局搜索：按内容匹配消息（JSON payload LIKE）。
  Future<List<ChatMessage>> searchMessages(
    String query, {
    int limit = 80,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return <ChatMessage>[];
    final rows = await db.query(
      'messages',
      where: 'payload LIKE ?',
      whereArgs: <Object?>['%$q%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows
        .map((r) => ChatMessage.fromJson(_decode(r['payload'])))
        .toList();
  }

  Future<Conversation?> getConversation(String id) async {
    final rows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Conversation.fromJson(_decode(rows.first['payload']));
  }

  Future<void> saveConversation(Conversation conversation) async {
    await db.insert(
      'conversations',
      <String, Object?>{
        'id': conversation.id,
        'profile_id': conversation.profileId,
        'title': conversation.title,
        'updated_at': conversation.updatedAt.millisecondsSinceEpoch,
        'pinned': conversation.pinned ? 1 : 0,
        'archived': conversation.archived ? 1 : 0,
        'payload': jsonEncode(conversation.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteConversation(String id) async {
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('conversations', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteAllConversations({String? profileId}) async {
    final where = profileId == null ? null : 'profile_id = ?';
    final args = profileId == null ? null : <Object?>[profileId];
    final rows = await db.query(
      'conversations',
      columns: ['id'],
      where: where,
      whereArgs: args,
    );
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.delete(
          'messages',
          where: 'session_id = ?',
          whereArgs: [row['id']],
        );
      }
      await txn.delete('conversations', where: where, whereArgs: args);
    });
  }

  // ---------------------------------------------------------------------------
  // 消息
  // ---------------------------------------------------------------------------

  Future<List<ChatMessage>> listMessages(String sessionId) async {
    final rows = await db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((r) => ChatMessage.fromJson(_decode(r['payload'])))
        .toList();
  }

  Future<void> saveMessage(ChatMessage message) async {
    await db.insert(
      'messages',
      <String, Object?>{
        'id': message.id,
        'session_id': message.sessionId,
        'role': message.role.name,
        'created_at': message.createdAt.millisecondsSinceEpoch,
        'payload': jsonEncode(message.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMessage(String id) async {
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMessagesFrom(
    String sessionId,
    DateTime fromInclusive,
  ) async {
    await db.delete(
      'messages',
      where: 'session_id = ? AND created_at >= ?',
      whereArgs: [sessionId, fromInclusive.millisecondsSinceEpoch],
    );
  }

  // ---------------------------------------------------------------------------
  // 备份辅助
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> dumpTable(String table) async {
    final rows = await db.query(table);
    return rows
        .map((r) => <String, dynamic>{
              ...r,
              if (r['payload'] is String)
                'payload': _decode(r['payload'] as String),
            })
        .toList();
  }

  /// 备份恢复：把整表行写回（payload 是 Map 时自动编码）。
  Future<void> importRows(
    String table,
    List<Map<String, dynamic>> rows, {
    bool replace = true,
  }) async {
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final row in rows) {
      final values = <String, Object?>{};
      row.forEach((key, value) {
        if (key == 'payload' && value is Map) {
          values[key] = jsonEncode(value);
        } else {
          values[key] = value;
        }
      });
      batch.insert(
        table,
        values,
        conflictAlgorithm:
            replace ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> countRows(String table) async {
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (result.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> clearTable(String table) async {
    await db.delete(table);
  }

  Future<void> wipeUserData() async {
    await db.transaction((txn) async {
      for (final table in <String>[
        'messages',
        'conversations',
        'memories',
        'entities',
        'relations',
        'episodes',
      ]) {
        await txn.delete(table);
      }
    });
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
