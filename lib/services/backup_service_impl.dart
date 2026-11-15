/// 全量备份 / 恢复实现。
///
/// 数据读写由数据层通过 [BackupRepository] 注入，本文件不直接依赖 sqflite，
/// 因此可以在没有数据库的单元测试中用内存实现替换。
///
/// 备份文件结构（v1）：
/// ```json
/// {
///   "version": 1,
///   "exportedAt": "2026-01-01T00:00:00.000Z",
///   "profiles": [...],
///   "conversations": [...],
///   "messages": [...],
///   "memories": [...]
/// }
/// ```
library;

import 'dart:convert';

import 'contracts.dart';

/// 当前备份格式版本。
const int backupFormatVersion = 1;

/// 备份服务实现。
class BackupServiceImpl implements BackupService {
  BackupServiceImpl({required BackupRepository repository})
      : _repository = repository;

  final BackupRepository _repository;

  /// 已知的数据表键名，用于校验文件是否像一份备份。
  static const List<String> _dataKeys = <String>[
    'profiles',
    'conversations',
    'messages',
    'memories',
  ];

  @override
  Future<String> exportAll() async {
    Map<String, dynamic> data;
    try {
      data = await _repository.exportData();
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(ApiErrorKind.unknown, '导出备份失败：$error');
    }

    final payload = <String, dynamic>{
      'version': backupFormatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      ...data,
    };
    try {
      return const JsonEncoder.withIndent('  ').convert(payload);
    } catch (error) {
      throw ApiException(ApiErrorKind.unknown, '备份数据无法序列化为 JSON：$error');
    }
  }

  @override
  Future<BackupSummary> importAll(String json, {bool replace = false}) async {
    if (json.trim().isEmpty) {
      throw const ApiException(ApiErrorKind.invalidRequest, '备份文件内容为空');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const ApiException(
        ApiErrorKind.invalidRequest,
        '备份文件不是合法的 JSON，请确认选择了正确的备份文件',
      );
    }

    final Map<String, dynamic> data;
    if (decoded is Map<String, dynamic>) {
      data = decoded;
    } else if (decoded is Map) {
      data = decoded.map((key, value) => MapEntry(key.toString(), value));
    } else {
      throw const ApiException(ApiErrorKind.invalidRequest, '备份文件格式不正确');
    }

    final rawVersion = data['version'];
    final version = rawVersion is num ? rawVersion.toInt() : backupFormatVersion;
    if (version > backupFormatVersion) {
      throw ApiException(
        ApiErrorKind.invalidRequest,
        '备份文件版本（v$version）高于当前应用支持的版本'
        '（v$backupFormatVersion），请先升级应用再导入',
      );
    }
    if (!_dataKeys.any(data.containsKey)) {
      throw const ApiException(
        ApiErrorKind.invalidRequest,
        '备份文件缺少对话 / 记忆数据，可能不是有效的 DeepSleep 备份',
      );
    }

    try {
      return await _repository.importData(data, replace: replace);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(ApiErrorKind.unknown, '导入备份失败：$error');
    }
  }
}
