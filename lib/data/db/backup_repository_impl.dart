/// 备份数据的 SQLite 实现。
library;

import '../models/memory_models.dart';
import '../models/profile_models.dart';
import '../../services/contracts.dart';
import 'app_database.dart';

class AppBackupRepository implements BackupRepository {
  AppBackupRepository(this._db);

  final AppDatabase _db;

  static const List<String> _tables = <String>[
    'profiles',
    'conversations',
    'messages',
    'memories',
    'entities',
    'relations',
    'episodes',
  ];

  @override
  Future<Map<String, dynamic>> exportData() async {
    final data = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    for (final table in _tables) {
      data[table] = await _db.dumpTable(table);
    }
    return data;
  }

  @override
  Future<BackupSummary> importData(
    Map<String, dynamic> data, {
    bool replace = false,
  }) async {
    if (replace) {
      await _db.wipeUserData();
    }
    for (final table in _tables) {
      final rows = (data[table] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) continue;
      await _db.importRows(table, rows, replace: true);
    }
    final profiles = await _db.countRows('profiles');
    final conversations = await _db.countRows('conversations');
    final messages = await _db.countRows('messages');
    final memories = await _db.countRows('memories');
    return BackupSummary(
      conversations: conversations,
      messages: messages,
      memories: memories,
      profiles: profiles,
    );
  }
}

/// 兼容：备份文件里保存的记忆类型统计（供 UI 展示，不参与恢复逻辑）。
class BackupPreview {
  const BackupPreview({
    required this.profiles,
    required this.conversations,
    required this.messages,
    required this.memories,
    required this.exportedAt,
  });

  final int profiles;
  final int conversations;
  final int messages;
  final int memories;
  final DateTime? exportedAt;

  static BackupPreview fromJson(Map<String, dynamic> data) {
    return BackupPreview(
      profiles: (data['profiles'] as List<dynamic>? ?? const []).length,
      conversations:
          (data['conversations'] as List<dynamic>? ?? const []).length,
      messages: (data['messages'] as List<dynamic>? ?? const []).length,
      memories: (data['memories'] as List<dynamic>? ?? const []).length,
      exportedAt: DateTime.tryParse(data['exportedAt'] as String? ?? ''),
    );
  }

  /// 统计各记忆类型数量（可选展示）。
  static Map<MemoryKind, int> countKinds(Map<String, dynamic> data) {
    final result = <MemoryKind, int>{};
    final rows = data['memories'] as List<dynamic>? ?? const [];
    for (final row in rows.whereType<Map>()) {
      final payload = row['payload'];
      if (payload is Map) {
        final item = MemoryItem.fromJson(Map<String, dynamic>.from(payload));
        result[item.kind] = (result[item.kind] ?? 0) + 1;
      }
    }
    return result;
  }

  /// 档案名称列表（导入预览用）。
  static List<String> profileNames(Map<String, dynamic> data) {
    final rows = data['profiles'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map>()
        .map((row) {
          final payload = row['payload'];
          if (payload is Map) {
            return UserProfile.fromJson(Map<String, dynamic>.from(payload)).name;
          }
          return '';
        })
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
