/// 设置与用户档案状态管理。
///
/// 普通设置存 SharedPreferences；三类密钥（DeepSeek / 搜索 / mem0）存
/// flutter_secure_storage，不进任何明文备份。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/utils/ids.dart';
import '../data/models/profile_models.dart';
import '../data/db/app_database.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    required SharedPreferences prefs,
    required FlutterSecureStorage secure,
    required AppDatabase database,
  })  : _prefs = prefs,
        _secure = secure,
        _db = database;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final AppDatabase _db;

  AppSettings _settings = const AppSettings();
  String _apiKey = '';
  String _searchApiKey = '';
  String _mem0ApiKey = '';
  List<UserProfile> _profiles = const <UserProfile>[];
  bool _initialized = false;

  AppSettings get settings => _settings;
  String get apiKey => _apiKey;
  String get searchApiKey => _searchApiKey;
  String get mem0ApiKey => _mem0ApiKey;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  bool get initialized => _initialized;
  List<UserProfile> get profiles => List<UserProfile>.unmodifiable(_profiles);

  UserProfile get activeProfile {
    if (_profiles.isEmpty) {
      return UserProfile(
        id: _settings.activeProfileId,
        name: '我',
        emoji: '🙂',
        createdAt: DateTime.now(),
        isDefault: true,
      );
    }
    for (final p in _profiles) {
      if (p.id == _settings.activeProfileId) return p;
    }
    return _profiles.first;
  }

  /// 当前用户 ID（记忆隔离维度，等价于 mem0 的 user_id）。
  String get userId => activeProfile.id;

  Future<void> load() async {
    _settings = _readSettings();
    await _loadProfiles();
    _apiKey = await _readSecret(StorageKeys.apiKey);
    _searchApiKey = await _readSecret(StorageKeys.searchApiKey);
    _mem0ApiKey = await _readSecret(StorageKeys.mem0ApiKey);

    final activeId = _settings.activeProfileId;
    final valid = _profiles.any((p) => p.id == activeId);
    if (!valid && _profiles.isNotEmpty) {
      _settings = _settings.copyWith(activeProfileId: _profiles.first.id);
      await _prefs.setString(
        StorageKeys.settings,
        jsonEncode(_settings.toJson()),
      );
    }
    _initialized = true;
    notifyListeners();
  }

  AppSettings _readSettings() {
    final raw = _prefs.getString(StorageKeys.settings);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
    } catch (_) {
      // 配置损坏时回到默认值。
    }
    return const AppSettings();
  }

  Future<void> update(AppSettings next) async {
    _settings = next;
    await _prefs.setString(StorageKeys.settings, jsonEncode(next.toJson()));
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    await _writeSecret(StorageKeys.apiKey, _apiKey);
    notifyListeners();
  }

  Future<void> setSearchApiKey(String key) async {
    _searchApiKey = key.trim();
    await _writeSecret(StorageKeys.searchApiKey, _searchApiKey);
    notifyListeners();
  }

  Future<void> setMem0ApiKey(String key) async {
    _mem0ApiKey = key.trim();
    await _writeSecret(StorageKeys.mem0ApiKey, _mem0ApiKey);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 用户档案
  // ---------------------------------------------------------------------------

  Future<void> _loadProfiles() async {
    var list = await _db.listProfiles();
    if (list.isEmpty) {
      final now = DateTime.now();
      final profile = UserProfile(
        id: 'default',
        name: '我',
        emoji: '🙂',
        createdAt: now,
        isDefault: true,
      );
      await _db.saveProfile(profile);
      list = <UserProfile>[profile];
    }
    _profiles = list;
  }

  Future<void> reloadProfiles() async {
    await _loadProfiles();
    notifyListeners();
  }

  Future<UserProfile> createProfile({
    required String name,
    String emoji = '🧑',
    String persona = '',
  }) async {
    final profile = UserProfile(
      id: Ids.newId('user'),
      name: name.trim().isEmpty ? '新用户' : name.trim(),
      emoji: emoji,
      persona: persona,
      createdAt: DateTime.now(),
    );
    await _db.saveProfile(profile);
    await _loadProfiles();
    notifyListeners();
    return profile;
  }

  Future<void> updateProfile(UserProfile profile) async {
    await _db.saveProfile(profile);
    await _loadProfiles();
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return; // 至少保留一个档案
    await _db.deleteProfile(id);
    await _loadProfiles();
    if (_settings.activeProfileId == id) {
      await update(_settings.copyWith(activeProfileId: _profiles.first.id));
    } else {
      notifyListeners();
    }
  }

  Future<void> switchProfile(String id) async {
    if (_settings.activeProfileId == id) return;
    if (!_profiles.any((p) => p.id == id)) return;
    await update(_settings.copyWith(activeProfileId: id));
  }

  // ---------------------------------------------------------------------------
  // 密钥读写
  // ---------------------------------------------------------------------------

  Future<String> _readSecret(String key) async {
    try {
      return await _secure.read(key: key) ?? '';
    } catch (_) {
      return _prefs.getString('${key}_fallback') ?? '';
    }
  }

  Future<void> _writeSecret(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {
      // 部分 ROM 上 KeyStore 不可用时退化为明文（仅本机）。
      await _prefs.setString('${key}_fallback', value);
    }
  }
}
