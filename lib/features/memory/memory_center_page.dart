/// 记忆中心：统计 metric 卡、检索筛选、可追溯来源的记忆列表，
/// 以及带曲线关系与实体详情卡的知识图谱。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/memory/contracts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/memory_models.dart';
import '../../state/app_services.dart';
import '../../state/memory_controller.dart';
import '../../widgets/soft_modal.dart';

/// 记忆中心页面。
class MemoryCenterPage extends StatefulWidget {
  const MemoryCenterPage({
    super.key,
    required this.services,
    this.initialQuery,
  });

  final AppServices services;

  /// 从全局搜索进入时携带的关键词。
  final String? initialQuery;

  @override
  State<MemoryCenterPage> createState() => _MemoryCenterPageState();
}

class _MemoryCenterPageState extends State<MemoryCenterPage> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Future<String?>> _titleCache = <String, Future<String?>>{};
  Timer? _debounce;
  int _tab = 0;

  MemoryController get _memories => widget.services.memories;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _searchController.text = initial;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _memories.refresh();
      _memories.loadGraph();
      if (initial.isNotEmpty) {
        _memories.setQuery(initial);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 交互
  // ---------------------------------------------------------------------------

  void _selectTab(int index) {
    if (_tab == index) return;
    setState(() => _tab = index);
    if (index == 1) _memories.loadGraph();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _memories.setQuery(value);
    });
  }

  Future<String?> _sessionTitle(String sessionId) {
    return _titleCache.putIfAbsent(sessionId, () async {
      try {
        final conversation =
            await widget.services.database.getConversation(sessionId);
        return conversation?.title;
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> _openSourceConversation(String sessionId) async {
    final navigator = Navigator.of(context);
    final services = widget.services;
    navigator.pop();
    await services.conversations.openConversation(sessionId);
  }

  Future<void> _clearAll() async {
    final confirmed = await showSoftConfirm(
      context: context,
      title: '清空记忆',
      description: '将清空当前用户的全部记忆、实体与关系，删除后不可恢复。'
          '\n\n对话记录不会被删除。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    await _memories.clearAll();
    messenger.showSnackBar(
      const SnackBar(content: Text('已清空当前用户的记忆')),
    );
  }

  Future<void> _deleteMemory(MemoryItem item) async {
    final confirmed = await showSoftConfirm(
      context: context,
      title: '删除记忆',
      description: '删除后不可恢复，确定要删除这条记忆吗？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    await _memories.deleteMemory(item.id);
  }

  Future<void> _editMemory(MemoryItem item) async {
    final updated = await showSoftSheet<MemoryItem>(
      context: context,
      title: '编辑记忆',
      child: _MemoryEditForm(item: item),
    );
    if (updated == null) return;
    await _memories.updateMemory(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('记忆已更新')),
    );
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆中心'),
        actions: <Widget>[
          IconButton(
            tooltip: '清空所有记忆',
            onPressed: _clearAll,
            iconSize: 20,
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListenableBuilder(
        listenable: _memories,
        builder: (context, _) {
          return Column(
            children: <Widget>[
              _buildMetrics(context),
              _buildTabs(context),
              Expanded(
                child: _tab == 0
                    ? _buildMemoryTab(context)
                    : _buildGraphTab(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetrics(BuildContext context) {
    final stats = _memories.stats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          _MetricCard(
            icon: Icons.psychology_outlined,
            label: '总记忆',
            value: stats.total,
          ),
          const SizedBox(width: AppSpacing.sm),
          _MetricCard(
            icon: Icons.scatter_plot_outlined,
            label: '实体',
            value: stats.entities,
          ),
          const SizedBox(width: AppSpacing.sm),
          _MetricCard(
            icon: Icons.hub_outlined,
            label: '关系',
            value: stats.relations,
          ),
          const SizedBox(width: AppSpacing.sm),
          _MetricCard(
            icon: Icons.archive_outlined,
            label: '已取代',
            value: stats.superseded,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final colors = context.colors;
    Widget tab(String label, int index) {
      final active = _tab == index;
      return InkWell(
        onTap: () => _selectTab(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? colors.textPrimary : colors.textTertiary,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                height: 2,
                width: 16,
                color: active ? colors.textPrimary : Colors.transparent,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          tab('记忆', 0),
          const SizedBox(width: AppSpacing.md),
          tab('知识图谱', 1),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 记忆列表
  // ---------------------------------------------------------------------------

  Widget _buildMemoryTab(BuildContext context) {
    final colors = context.colors;
    final error = _memories.error;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            10,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: _buildSearchField(context),
        ),
        _buildKindChips(context),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                style: TextStyle(fontSize: 12, color: colors.danger),
              ),
            ),
          ),
        Expanded(child: _buildMemoryList(context)),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = context.colors;
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(fontSize: 14, color: colors.textPrimary),
        cursorHeight: 16,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.bgHover,
          hintText: '搜索记忆内容',
          hintStyle: TextStyle(fontSize: 14, color: colors.textTertiary),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: colors.textTertiary,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _searchController.clear();
                    _memories.setQuery('');
                    setState(() {});
                  },
                  icon: Icon(Icons.close_rounded, color: colors.textTertiary),
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 40),
          contentPadding: EdgeInsets.zero,
          border: noBorder,
          enabledBorder: noBorder,
          focusedBorder: noBorder,
        ),
      ),
    );
  }

  Widget _buildKindChips(BuildContext context) {
    final selectedKind = _memories.kind;
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: <Widget>[
          _buildKindChip(
            context,
            label: '全部',
            selected: selectedKind == null,
            onTap: () => _memories.setKind(null),
          ),
          for (final kind in MemoryKind.values)
            _buildKindChip(
              context,
              label: kind.label,
              selected: selectedKind == kind,
              onTap: () => _memories.setKind(kind),
            ),
        ],
      ),
    );
  }

  Widget _buildKindChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? colors.brandSoft : colors.bgHover,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? colors.brandText : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryList(BuildContext context) {
    final colors = context.colors;
    final items = _memories.items;
    if (items.isEmpty) {
      if (_memories.loading) {
        return _buildSkeleton(context);
      }
      return _buildMemoryEmptyState(context);
    }

    return ListView.separated(
      padding: const EdgeInsets.only(
        top: AppSpacing.xs,
        bottom: AppSpacing.xxl,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        color: colors.border,
        indent: AppSpacing.lg,
        endIndent: AppSpacing.lg,
      ),
      itemBuilder: (context, index) =>
          _buildMemoryRow(context, items[index]),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      children: <Widget>[
        for (var i = 0; i < 5; i++)
          Container(
            height: 64,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colors.bgHover,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      ],
    );
  }

  Widget _buildMemoryEmptyState(BuildContext context) {
    final colors = context.colors;
    final filtered =
        _memories.query.trim().isNotEmpty || _memories.kind != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              filtered ? Icons.search_off_rounded : Icons.psychology_outlined,
              size: 30,
              color: colors.brandText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            filtered ? '没有找到相关记忆' : '还没有记忆',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            filtered ? '换个关键词或类型试试' : '开启长期记忆后，聊过的内容会沉淀成知识网。',
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryRow(BuildContext context, MemoryItem item) {
    final colors = context.colors;
    final importance = item.importance.clamp(0.0, 1.0).toDouble();
    final meta = '${item.kind.label} · 重要度 ${(importance * 100).round()}% · '
        '${formatRelative(item.updatedAt)} · 引用 ${item.accessCount} 次';
    final sourceId = item.sourceSessionId;

    return InkWell(
      onTap: () => _editMemory(item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textTertiary,
                    ),
                  ),
                  if (sourceId != null) ...<Widget>[
                    const SizedBox(height: 2),
                    _SourceLink(
                      titleFuture: _sessionTitle(sourceId),
                      onTap: () => _openSourceConversation(sourceId),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: item.pinned ? '取消置顶' : '置顶',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              iconSize: 18,
              onPressed: () => _memories.togglePin(item),
              icon: Icon(
                item.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: item.pinned ? colors.brandText : colors.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            IconButton(
              tooltip: '编辑',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              iconSize: 18,
              onPressed: () => _editMemory(item),
              icon: Icon(Icons.edit_outlined, color: colors.textTertiary),
            ),
            const SizedBox(width: AppSpacing.md),
            IconButton(
              tooltip: '删除',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              iconSize: 18,
              onPressed: () => _deleteMemory(item),
              icon: Icon(
                Icons.delete_outline_rounded,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 知识图谱
  // ---------------------------------------------------------------------------

  Widget _buildGraphTab(BuildContext context) {
    final graph = _memories.graph;
    final colors = context.colors;
    if (graph.isEmpty) {
      if (_memories.loading) {
        return const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hub_outlined, size: 34, color: colors.brandText),
            ),
            const SizedBox(height: 14),
            Text(
              '还没有形成知识图谱',
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '多聊几轮后，实体与关系会在这里连成网络。',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _memories.loadGraph(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    return _MemoryGraphView(graph: graph);
  }
}

// -----------------------------------------------------------------------------
// 统计 metric 卡
// -----------------------------------------------------------------------------

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: colors.bgHover,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.brandSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: colors.brandText),
            ),
            const SizedBox(height: 8),
            Text(
              '$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 来源会话链接
// -----------------------------------------------------------------------------

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.titleFuture, required this.onTap});

  final Future<String?> titleFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FutureBuilder<String?>(
      future: titleFuture,
      builder: (context, snapshot) {
        final title = snapshot.data;
        if (title == null || title.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.forum_outlined,
                  size: 12,
                  color: colors.brandText,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '来源：$title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.brandText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 知识图谱可视化
// -----------------------------------------------------------------------------

class _GraphLayout {
  const _GraphLayout({
    required this.positions,
    required this.radii,
    required this.fontSizes,
  });

  final Map<String, Offset> positions;
  final Map<String, double> radii;
  final Map<String, double> fontSizes;

  static const _GraphLayout empty = _GraphLayout(
    positions: <String, Offset>{},
    radii: <String, double>{},
    fontSizes: <String, double>{},
  );
}

class _MemoryGraphView extends StatefulWidget {
  const _MemoryGraphView({super.key, required this.graph});

  final MemoryGraphSnapshot graph;

  @override
  State<_MemoryGraphView> createState() => _MemoryGraphViewState();
}

class _MemoryGraphViewState extends State<_MemoryGraphView> {
  String? _selected;

  @override
  void didUpdateWidget(covariant _MemoryGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.graph != widget.graph) {
      _selected = null;
    }
  }

  _GraphLayout _computeLayout(Size size) {
    final entities = widget.graph.entities;
    if (entities.isEmpty || size.width <= 0 || size.height <= 0) {
      return _GraphLayout.empty;
    }
    final center = Offset(size.width / 2, size.height / 2);
    final maxRing = math.max(
      24.0,
      math.min(size.width, size.height) / 2 - 46,
    );
    final sorted = List<MemoryEntity>.from(entities)
      ..sort((a, b) => b.mentionCount.compareTo(a.mentionCount));
    final maxMention =
        sorted.first.mentionCount <= 0 ? 1 : sorted.first.mentionCount;

    final positions = <String, Offset>{};
    final radii = <String, double>{};
    final fontSizes = <String, double>{};

    final useTwoRings = sorted.length > 8;
    final innerCount =
        useTwoRings ? math.max(3, (sorted.length * 0.38).ceil()) : 0;

    for (var i = 0; i < sorted.length; i++) {
      final entity = sorted[i];
      final isInner = useTwoRings && i < innerCount;
      final ringCount = isInner ? innerCount : sorted.length - innerCount;
      final ringIndex = isInner ? i : i - innerCount;
      final ringRadius = isInner ? maxRing * 0.44 : maxRing;
      final angle = -math.pi / 2 +
          (2 * math.pi * ringIndex) / math.max(1, ringCount) +
          (isInner ? math.pi / 7 : 0);
      final ratio =
          (entity.mentionCount / maxMention).clamp(0.0, 1.0).toDouble();
      final nodeRadius = 8.0 + 14.0 * ratio;

      positions[entity.name] = center +
          Offset(math.cos(angle) * ringRadius, math.sin(angle) * ringRadius);
      radii[entity.name] = nodeRadius;
      fontSizes[entity.name] = 11.0;
    }

    return _GraphLayout(
      positions: positions,
      radii: radii,
      fontSizes: fontSizes,
    );
  }

  Set<String> _neighbors(String name) {
    final result = <String>{name};
    for (final relation in widget.graph.relations) {
      if (relation.sourceName == name) result.add(relation.targetName);
      if (relation.targetName == name) result.add(relation.sourceName);
    }
    return result;
  }

  void _handleTap(Offset position, _GraphLayout layout) {
    String? hit;
    var bestDistance = double.infinity;
    layout.positions.forEach((name, nodeCenter) {
      final radius = layout.radii[name] ?? 10;
      final distance = (nodeCenter - position).distance;
      if (distance <= radius + 10 && distance < bestDistance) {
        hit = name;
        bestDistance = distance;
      }
    });
    setState(() {
      _selected = hit == _selected ? null : hit;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final graph = widget.graph;
    final selected = _selected;
    return Column(
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
                constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
              );
              final layout = _computeLayout(size);
              final neighbors =
                  selected == null ? const <String>{} : _neighbors(selected);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    _handleTap(details.localPosition, layout),
                child: CustomPaint(
                  painter: _GraphPainter(
                    entities: graph.entities,
                    relations: graph.relations,
                    layout: layout,
                    selected: selected,
                    neighbors: neighbors,
                    colors: colors,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
        if (selected != null) _buildEntityCard(context, selected),
      ],
    );
  }

  Widget _buildEntityCard(BuildContext context, String name) {
    final colors = context.colors;
    MemoryEntity? entity;
    for (final candidate in widget.graph.entities) {
      if (candidate.name == name) {
        entity = candidate;
        break;
      }
    }
    if (entity == null) return const SizedBox.shrink();

    final relations = widget.graph.relations
        .where((relation) =>
            relation.sourceName == name || relation.targetName == name)
        .toList(growable: false);
    final memories = widget.graph.memories
        .where((memory) => memory.entities.contains(name))
        .toList(growable: false);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      entity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    entity.type,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '提及 ${entity.mentionCount} 次',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textTertiary,
                    ),
                  ),
                  IconButton(
                    tooltip: '收起',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    iconSize: 16,
                    onPressed: () => setState(() => _selected = null),
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  _countChip(
                    context,
                    icon: Icons.link_rounded,
                    label: '${relations.length} 条关系',
                  ),
                  const SizedBox(width: 8),
                  _countChip(
                    context,
                    icon: Icons.psychology_outlined,
                    label: '${memories.length} 条关联记忆',
                  ),
                ],
              ),
              if (relations.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                for (final relation in relations.take(4))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${relation.sourceName} —${relation.relation}→ '
                      '${relation.targetName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
              if (memories.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                for (final memory in memories.take(2))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '· ${memory.content}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.bgHover,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 环形布局画笔：关系用曲线连接，选中高亮邻接节点。
class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.entities,
    required this.relations,
    required this.layout,
    required this.selected,
    required this.neighbors,
    required this.colors,
  });

  final List<MemoryEntity> entities;
  final List<MemoryRelation> relations;
  final _GraphLayout layout;
  final String? selected;
  final Set<String> neighbors;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    _paintRelations(canvas);
    _paintNodes(canvas, size);
  }

  void _paintRelations(Canvas canvas) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final relation in relations) {
      final from = layout.positions[relation.sourceName];
      final to = layout.positions[relation.targetName];
      if (from == null || to == null) continue;
      if (relation.sourceName == relation.targetName) continue;

      final isRelated = selected == null ||
          relation.sourceName == selected ||
          relation.targetName == selected;
      stroke
        ..strokeWidth = selected != null && isRelated ? 1.4 : 1
        ..color = selected != null && isRelated
            ? colors.brand.withValues(alpha: 0.35)
            : colors.border;

      final direction = to - from;
      final distance = direction.distance;
      final normal = distance == 0
          ? Offset.zero
          : Offset(-direction.dy / distance, direction.dx / distance);
      final curve = distance * 0.12;
      final control = Offset(
        (from.dx + to.dx) / 2 + normal.dx * curve,
        (from.dy + to.dy) / 2 + normal.dy * curve,
      );
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
      canvas.drawPath(path, stroke);

      if (selected != null && isRelated) {
        _paintText(
          canvas,
          relation.relation,
          control,
          10.5,
          colors.textTertiary,
        );
      }
    }
  }

  void _paintNodes(Canvas canvas, Size size) {
    for (final entity in entities) {
      final center = layout.positions[entity.name];
      if (center == null) continue;
      final radius = layout.radii[entity.name] ?? 8;
      final isSelected = selected == entity.name;
      final isNeighbor = neighbors.contains(entity.name);

      canvas.drawCircle(
        center,
        radius,
        Paint()..color = isSelected ? colors.brand : colors.brandSoft,
      );
      if (isSelected || (selected != null && isNeighbor)) {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2 : 1.2
            ..color = colors.brand,
        );
      }

      final labelColor = isSelected
          ? colors.textPrimary
          : (selected == null || isNeighbor
              ? colors.textSecondary
              : colors.textTertiary);
      final fontSize = layout.fontSizes[entity.name] ?? 11;
      final anchor = center.dy + radius + 3 > size.height - 14
          ? Offset(center.dx, center.dy - radius - fontSize - 4)
          : Offset(center.dx, center.dy + radius + 3);
      _paintText(canvas, entity.name, anchor, fontSize, labelColor);
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchor,
    double fontSize,
    Color color,
  ) {
    if (text.trim().isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 96);
    painter.paint(canvas, Offset(anchor.dx - painter.width / 2, anchor.dy));
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.entities != entities ||
        oldDelegate.relations != relations ||
        oldDelegate.colors != colors;
  }
}

// -----------------------------------------------------------------------------
// 记忆编辑表单（软弹窗内）
// -----------------------------------------------------------------------------

class _MemoryEditForm extends StatefulWidget {
  const _MemoryEditForm({super.key, required this.item});

  final MemoryItem item;

  @override
  State<_MemoryEditForm> createState() => _MemoryEditFormState();
}

class _MemoryEditFormState extends State<_MemoryEditForm> {
  late final TextEditingController _contentController;
  late MemoryKind _kind;
  late double _importance;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.item.content);
    _kind = widget.item.kind;
    _importance = widget.item.importance.clamp(0.0, 1.0).toDouble();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    Navigator.of(context).pop(
      widget.item.copyWith(
        content: content,
        kind: _kind,
        importance: _importance,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _contentController,
            maxLines: 5,
            minLines: 3,
            maxLength: 500,
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: const InputDecoration(
              labelText: '记忆内容',
              hintText: '用一句自然语言描述这条记忆',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Text(
                '类型',
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              ),
              const Spacer(),
              DropdownButton<MemoryKind>(
                value: _kind,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                isDense: true,
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: colors.textTertiary,
                ),
                style: TextStyle(
                  fontSize: 13.5,
                  color: colors.textSecondary,
                ),
                items: <DropdownMenuItem<MemoryKind>>[
                  for (final kind in MemoryKind.values)
                    DropdownMenuItem<MemoryKind>(
                      value: kind,
                      child: Text(kind.label),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _kind = value);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Text(
                '重要度',
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              ),
              const Spacer(),
              Text(
                '${(_importance * 100).round()}%',
                style: TextStyle(fontSize: 12.5, color: colors.textTertiary),
              ),
            ],
          ),
          Slider(
            value: _importance,
            min: 0,
            max: 1,
            divisions: 20,
            label: '${(_importance * 100).round()}%',
            onChanged: (value) => setState(() => _importance = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                ),
                child: const Text('取消'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _save,
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
