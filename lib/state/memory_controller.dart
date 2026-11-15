/// 记忆中心状态管理：列表、检索、编辑、删除、知识图谱、统计。
library;

import 'package:flutter/foundation.dart';

import '../core/memory/contracts.dart';
import '../data/models/memory_models.dart';
import 'settings_controller.dart';

class MemoryController extends ChangeNotifier {
  MemoryController({
    required MemoryEngine engine,
    required SettingsController settings,
  })  : _engine = engine,
        _settings = settings;

  final MemoryEngine _engine;
  final SettingsController _settings;

  List<MemoryItem> _items = <MemoryItem>[];
  MemoryStats _stats = const MemoryStats();
  MemoryGraphSnapshot _graph = const MemoryGraphSnapshot();
  bool _loading = false;
  bool _disposed = false;
  String _query = '';
  MemoryKind? _kind;
  String? _error;

  List<MemoryItem> get items => List<MemoryItem>.unmodifiable(_items);
  MemoryStats get stats => _stats;
  MemoryGraphSnapshot get graph => _graph;
  bool get loading => _loading;
  String get query => _query;
  MemoryKind? get kind => _kind;
  String? get error => _error;
  bool get isEmpty => _items.isEmpty;

  String get _userId => _settings.userId;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    _notify();
    try {
      _stats = await _engine.stats(_userId);
      _items = await _engine.listMemories(
        userId: _userId,
        kind: _kind,
        query: _query.trim().isEmpty ? null : _query.trim(),
        limit: 300,
      );
    } catch (e) {
      _error = '记忆加载失败：$e';
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> loadGraph() async {
    try {
      _graph = await _engine.graph(_userId, maxNodes: 60);
      _notify();
    } catch (e) {
      _error = '知识图谱加载失败：$e';
      _notify();
    }
  }

  Future<void> setQuery(String value) async {
    _query = value;
    await refresh();
  }

  Future<void> setKind(MemoryKind? kind) async {
    _kind = kind;
    await refresh();
  }

  Future<void> updateMemory(MemoryItem item) async {
    try {
      await _engine.updateMemory(item);
      await refresh();
    } catch (e) {
      _error = '保存记忆失败：$e';
      _notify();
    }
  }

  Future<void> togglePin(MemoryItem item) async {
    await updateMemory(item.copyWith(pinned: !item.pinned));
  }

  Future<void> deleteMemory(String id) async {
    try {
      await _engine.deleteMemory(_userId, id);
      _items = _items.where((m) => m.id != id).toList();
      await refresh();
    } catch (e) {
      _error = '删除记忆失败：$e';
      _notify();
    }
  }

  Future<void> clearAll() async {
    try {
      // 逐个删除，本地与 mem0 两种后端都适用。
      final current = await _engine.listMemories(userId: _userId, limit: 500);
      for (final item in current) {
        await _engine.deleteMemory(_userId, item.id);
      }
      _items = <MemoryItem>[];
      await refresh();
      await loadGraph();
    } catch (e) {
      _error = '清空记忆失败：$e';
      _notify();
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
