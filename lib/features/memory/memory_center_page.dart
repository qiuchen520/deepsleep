/// 记忆中心：统计概览、记忆检索/筛选/编辑/删除，以及知识图谱可视化。
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

/// 记忆中心页面。
class MemoryCenterPage extends StatefulWidget {
  const MemoryCenterPage({super.key, required this.services});

  final AppServices services;

  @override
  State<MemoryCenterPage> createState() => _MemoryCenterPageState();
}

class _MemoryCenterPageState extends State<MemoryCenterPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  int _tab = 0;

  MemoryController get _memories => widget.services.memories;

  @override
  void initState() {
    super.initState();
    // 放到首帧之后加载，避免在构建过程中同步触发监听者重建。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _memories.refresh();
      _memories.loadGraph();
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

  Future<void> _clearAll() async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清空记忆'),
          content: const Text(
            '将清空当前用户的全部记忆、实体与关系，删除后不可恢复。\n\n'
            '对话记录不会被删除。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final messenger = ScaffoldMessenger.of(context);
    await _memories.clearAll();
    messenger.showSnackBar(
      const SnackBar(content: Text('已清空当前用户的记忆')),
    );
  }

  Future<void> _deleteMemory(MemoryItem item) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除记忆'),
          content: const Text('删除后不可恢复，确定要删除这条记忆吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _memories.deleteMemory(item.id);
  }

  Future<void> _editMemory(MemoryItem item) async {
    final updated = await showModalBottomSheet<MemoryItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MemoryEditSheet(item: item),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: _buildStatsCard(context),
              ),
              _buildTabSwitch(context),
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

  Widget _buildStatsCard(BuildContext context) {
    final colors = context.colors;
    final stats = _memories.stats;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          _buildStatItem(context, '总记忆', stats.total, colors.brand),
          _buildStatDivider(context),
          _buildStatItem(context, '实体', stats.entities, colors.success),
          _buildStatDivider(context),
          _buildStatItem(context, '关系', stats.relations, colors.warning),
          _buildStatDivider(context),
          _buildStatItem(context, '已取代', stats.superseded, colors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    int value,
    Color color,
  ) {
    final colors = context.colors;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: context.colors.border,
    );
  }

  Widget _buildTabSwitch(BuildContext context) {
    final colors = context.colors;
    Widget tab(String label, IconData icon, int index) {
      final selected = _tab == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => _selectTab(index),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected ? colors.bgBase : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? colors.brand : colors.textTertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color:
                        selected ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          tab('记忆', Icons.notes, 0),
          tab('知识图谱', Icons.hub, 1),
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
            0,
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
            child: Text(
              error,
              style: TextStyle(fontSize: 12, color: colors.danger),
            ),
          ),
        Expanded(child: _buildMemoryList(context)),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.bgElevated,
          hintText: '搜索记忆内容',
          hintStyle: TextStyle(fontSize: 13, color: colors.textTertiary),
          prefixIcon: Icon(Icons.search, size: 17, color: colors.textTertiary),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _searchController.clear();
                    _memories.setQuery('');
                    setState(() {});
                  },
                  icon: Icon(Icons.close, color: colors.textTertiary),
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: colors.brand, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _buildKindChips(BuildContext context) {
    final selectedKind = _memories.kind;
    return SizedBox(
      height: 40,
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
      child: Center(
        child: ChoiceChip(
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? colors.brandText : colors.textSecondary,
            ),
          ),
          selected: selected,
          showCheckmark: false,
          selectedColor: colors.brandSoft,
          backgroundColor: colors.bgElevated,
          side: BorderSide(
            color: selected ? colors.brand : colors.border,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => onTap(),
        ),
      ),
    );
  }

  Widget _buildMemoryList(BuildContext context) {
    final items = _memories.items;
    if (items.isEmpty) {
      if (_memories.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildMemoryEmptyState(context);
    }

    final sessionTitles = <String, String>{
      for (final conversation in widget.services.conversations.conversations)
        conversation.id: conversation.title,
    };

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _buildMemoryCard(
        context,
        items[index],
        sessionTitles,
      ),
    );
  }

  Widget _buildMemoryEmptyState(BuildContext context) {
    final colors = context.colors;
    final filtered =
        _memories.query.trim().isNotEmpty || _memories.kind != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              filtered ? Icons.search_off : Icons.psychology_outlined,
              size: 36,
              color: colors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              filtered ? '没有找到相关记忆' : '还没有记忆',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              filtered
                  ? '换个关键词或类型试试'
                  : '开启长期记忆后，聊过的内容会自动沉淀成知识网。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(
    BuildContext context,
    MemoryItem item,
    Map<String, String> sessionTitles,
  ) {
    final colors = context.colors;
    final kindColor = _kindColor(context, item.kind);
    final sourceTitle = item.sourceSessionId == null
        ? null
        : sessionTitles[item.sourceSessionId];
    final importance = item.importance.clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: item.pinned
              ? colors.brand.withValues(alpha: 0.4)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: kindColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  item.kind.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: kindColor,
                  ),
                ),
              ),
              if (item.status == MemoryStatus.superseded)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.bgActive,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      '已取代',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              if (item.pinned)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.push_pin,
                    size: 12,
                    color: colors.brand,
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: item.pinned ? '取消置顶' : '置顶',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                onPressed: () => _memories.togglePin(item),
                icon: Icon(
                  item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: item.pinned ? colors.brand : colors.textTertiary,
                ),
              ),
              IconButton(
                tooltip: '编辑',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                onPressed: () => _editMemory(item),
                icon: Icon(
                  Icons.edit_outlined,
                  color: colors.textSecondary,
                ),
              ),
              IconButton(
                tooltip: '删除',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                onPressed: () => _deleteMemory(item),
                icon: Icon(
                  Icons.delete_outline,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Text(
              item.content,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(Icons.star_rounded, size: 13, color: colors.warning),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: importance,
                      minHeight: 4,
                      backgroundColor: colors.bgActive,
                      color: colors.warning,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${(importance * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: 2,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      formatRelative(item.updatedAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                if (sourceTitle != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.forum_outlined,
                        size: 12,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          '来源：$sourceTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.bolt_outlined,
                      size: 12,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '引用 ${item.accessCount} 次',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _kindColor(BuildContext context, MemoryKind kind) {
    final colors = context.colors;
    switch (kind) {
      case MemoryKind.fact:
        return colors.brand;
      case MemoryKind.preference:
        return colors.warning;
      case MemoryKind.profile:
        return colors.success;
      case MemoryKind.event:
        return colors.brandText;
      case MemoryKind.task:
        return colors.danger;
      case MemoryKind.relation:
        return colors.textSecondary;
    }
  }

  // ---------------------------------------------------------------------------
  // 知识图谱
  // ---------------------------------------------------------------------------

  Widget _buildGraphTab(BuildContext context) {
    final graph = _memories.graph;
    if (graph.isEmpty) {
      if (_memories.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final colors = context.colors;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.hub, size: 36, color: colors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text(
                '还没有形成知识图谱',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '多聊几轮后，实体与它们之间的关系会在这里连成网络。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: () => _memories.loadGraph(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }

    return _MemoryGraphView(
      graph: graph,
      onRefresh: () => _memories.loadGraph(),
    );
  }
}

// -----------------------------------------------------------------------------
// 知识图谱可视化
// -----------------------------------------------------------------------------

/// 环形布局结果：每个实体名的圆心、半径与标签字号。
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
  const _MemoryGraphView({super.key, required this.graph, required this.onRefresh});

  final MemoryGraphSnapshot graph;
  final Future<void> Function() onRefresh;

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
    final maxMention = sorted.first.mentionCount <= 0
        ? 1
        : sorted.first.mentionCount;

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
      final nodeRadius = 9.0 + 13.0 * ratio;

      positions[entity.name] = center +
          Offset(math.cos(angle) * ringRadius, math.sin(angle) * ringRadius);
      radii[entity.name] = nodeRadius;
      fontSizes[entity.name] = 9.5 + 3.0 * ratio;
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
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
                  onTapUp: (details) => _handleTap(details.localPosition, layout),
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
        ),
        if (selected != null)
          _buildEntityPanel(context, selected)
        else
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.touch_app_outlined,
                  size: 13,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '点击节点查看实体详情 · 圆越大提及越多',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: '刷新图谱',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => widget.onRefresh(),
                  icon: Icon(Icons.refresh, color: colors.textTertiary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEntityPanel(BuildContext context, String name) {
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
        .take(6)
        .toList(growable: false);
    final memories = widget.graph.memories
        .where((memory) => memory.entities.contains(name))
        .take(3)
        .toList(growable: false);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 165),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      fontSize: 10.5,
                      color: colors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '提及 ${entity.mentionCount} 次',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colors.textTertiary,
                    ),
                  ),
                  IconButton(
                    tooltip: '收起',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: () => setState(() => _selected = null),
                    icon: Icon(Icons.close, color: colors.textTertiary),
                  ),
                ],
              ),
              if (relations.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '关系',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 3,
                  children: <Widget>[
                    for (final relation in relations)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.bgActive,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          '${relation.sourceName} —${relation.relation}→ ${relation.targetName}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (memories.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '相关记忆',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 3),
                for (final memory in memories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '· ${memory.content}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: colors.textSecondary,
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
}

/// 环形布局的知识图谱画笔：关系为边、实体为节点，选中时高亮邻接关系。
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
    final stroke = Paint()..style = PaintingStyle.stroke;
    final showAllLabels = relations.length <= 14;
    for (final relation in relations) {
      final from = layout.positions[relation.sourceName];
      final to = layout.positions[relation.targetName];
      if (from == null || to == null) continue;
      if (relation.sourceName == relation.targetName) continue;

      final isRelated = selected == null ||
          relation.sourceName == selected ||
          relation.targetName == selected;
      stroke
        ..color = isRelated
            ? colors.brand.withValues(alpha: selected == null ? 0.26 : 0.62)
            : colors.border
        ..strokeWidth = isRelated ? (selected == null ? 1.0 : 1.6) : 0.7;
      canvas.drawLine(from, to, stroke);

      if (isRelated && (selected != null || showAllLabels)) {
        final midpoint = Offset(
          (from.dx + to.dx) / 2,
          (from.dy + to.dy) / 2,
        );
        _paintText(
          canvas,
          relation.relation,
          midpoint,
          8.5,
          colors.textTertiary.withValues(alpha: selected == null ? 0.75 : 1),
          maxWidth: 90,
        );
      }
    }
  }

  void _paintNodes(Canvas canvas, Size size) {
    final hasSelection = selected != null;
    for (final entity in entities) {
      final center = layout.positions[entity.name];
      if (center == null) continue;
      final radius = layout.radii[entity.name] ?? 10;
      final isSelected = selected == entity.name;
      final isNeighbor = !isSelected && neighbors.contains(entity.name);
      final dimmed = hasSelection && !isSelected && !isNeighbor;

      final fill = Paint()
        ..color = isSelected
            ? colors.brand
            : colors.brand.withValues(
                alpha: dimmed ? 0.05 : (isNeighbor ? 0.3 : 0.18),
              );
      canvas.drawCircle(center, radius, fill);

      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.2 : 1.1
        ..color = isSelected
            ? colors.brand
            : (isNeighbor
                ? colors.brand.withValues(alpha: 0.7)
                : colors.borderStrong);
      canvas.drawCircle(center, radius, border);

      final labelColor = isSelected
          ? colors.brandText
          : (dimmed ? colors.textTertiary : colors.textSecondary);
      final fontSize = layout.fontSizes[entity.name] ?? 10;
      final labelAnchor = center.dy + radius + 3 > size.height - 14
          ? Offset(center.dx, center.dy - radius - fontSize - 5)
          : Offset(center.dx, center.dy + radius + 3);
      _paintText(
        canvas,
        entity.name,
        labelAnchor,
        fontSize,
        labelColor,
        maxWidth: 96,
        centerHorizontally: true,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchor,
    double fontSize,
    Color color, {
    double maxWidth = 96,
    bool centerHorizontally = true,
  }) {
    if (text.trim().isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final offset = centerHorizontally
        ? Offset(anchor.dx - painter.width / 2, anchor.dy)
        : anchor;
    painter.paint(canvas, offset);
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
// 记忆编辑弹窗
// -----------------------------------------------------------------------------

class _MemoryEditSheet extends StatefulWidget {
  const _MemoryEditSheet({super.key, required this.item});

  final MemoryItem item;

  @override
  State<_MemoryEditSheet> createState() => _MemoryEditSheetState();
}

class _MemoryEditSheetState extends State<_MemoryEditSheet> {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '编辑记忆',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                const Spacer(),
                DropdownButton<MemoryKind>(
                  value: _kind,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
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
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Text(
                  '重要度',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
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
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
}
