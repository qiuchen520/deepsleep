/// 历史记录导入导出门面：支持 DeepSeek 官方导出 ZIP（v3）以及本应用备份。
library;

import 'dart:typed_data';

import '../data/db/app_database.dart';
import '../data/models/chat_models.dart';
import 'contracts.dart';
import 'deepseek_history_archive.dart';

class HistoryImportPreview {
  const HistoryImportPreview({
    required this.ok,
    this.format = '',
    this.conversations = 0,
    this.messages = 0,
    this.attachments = 0,
    this.conflicts = 0,
    this.error,
  });

  final bool ok;
  final String format;
  final int conversations;
  final int messages;
  final int attachments;
  final int conflicts;
  final String? error;
}

class HistoryTransferService {
  HistoryTransferService({
    required AppDatabase database,
    required BackupService backup,
  })  : _db = database,
        _backup = backup;

  final AppDatabase _db;
  final BackupService _backup;

  /// 校验并预览 DeepSeek ZIP / 本应用备份。
  Future<HistoryImportPreview> preview(Uint8List bytes, String fileName) async {
    try {
      if (fileName.toLowerCase().endsWith('.zip')) {
        final preview = DeepSeekHistoryArchive.preview(bytes);
        return HistoryImportPreview(
          ok: preview.ok,
          format: preview.format,
          conversations: preview.conversations,
          messages: preview.messages,
          attachments: preview.attachments,
          conflicts: preview.conflicts,
          error: preview.error,
        );
      }
      return const HistoryImportPreview(
        ok: false,
        error: '目前支持 DeepSeek 导出的 .zip 历史对话文件',
      );
    } catch (e) {
      return HistoryImportPreview(ok: false, error: '$e');
    }
  }

  /// 导入 DeepSeek ZIP；[replace] 为 false 时合并。
  Future<String> importDeepSeekZip(Uint8List bytes, {bool replace = true}) async {
    final result = await DeepSeekHistoryArchive.importInto(
      database: _db,
      zipBytes: bytes,
      replace: replace,
    );
    return '已导入 ${result.conversations} 个对话、${result.messages} 条消息';
  }

  /// 导出为 DeepSeek 兼容 ZIP。
  Future<Uint8List> exportDeepSeekZip() async {
    final conversations = await _db.listConversations();
    final messagesBySession = <String, List<ChatMessage>>{};
    for (final c in conversations) {
      messagesBySession[c.id] = await _db.listMessages(c.id);
    }
    return DeepSeekHistoryArchive.export(
      conversations: conversations,
      messagesBySession: messagesBySession,
    );
  }

  /// 兼容原有本应用备份 JSON 导入。
  Future<BackupSummary> importOwnBackup(String json, {bool replace = false}) {
    return _backup.importAll(json, replace: replace);
  }
}
