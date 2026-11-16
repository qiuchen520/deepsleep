/// 会话侧栏（对齐 DeepSeek 平板版参考图）。
///
/// 结构：顶部固定搜索框 → 置顶分组（可折叠）+ 今天 / 昨天 / 更早分组 →
/// 底部个人信息行（头像菜单：切换档案 / 记忆中心 / 设置 / 关于）。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/profile_models.dart';
import '../../services/contracts.dart';
import '../../state/app_services.dart';
import '../../widgets/soft_menu.dart';
import '../../widgets/soft_modal.dart';
import '../search/global_search_page.dart';

/// 会话侧栏。
///
/// 宽屏时由 [RootShell] 常驻显示（[onClose] 为 null）；
/// 窄屏时作为 Drawer 内容，[onClose] 用于关闭抽屉。
class SessionSidebar extends StatelessWidget {
  const SessionSidebar({
    super.key,
    required this.services,
    required this.onOpenSettings,
    required this.onOpenMemory,
    this.onClose,
  });

  final AppServices services;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMemory;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _SidebarBody(
      services: services,
      onOpenSettings: onOpenSettings,
      onOpenMemory: onOpenMemory,
      onClose: onClose,
    );
  }
}

/// 会话条目菜单动作。
enum _ConvAction { rename, pin, export, select, delete }

/// 底部个人信息菜单动作。
enum _ProfileAction { switchProfile, memory, settings, about }

class _SidebarBody extends StatefulWidget {
  const _SidebarBody({
    super.key,
    required this.services,
    required this.onOpenSettings,
    required this.onOpenMemory,
    this.onClose,
  });

  final AppServices services;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMemory;
  final VoidCallback? onClose;

  @override
  State<_SidebarBody> createState() => _SidebarBodyState();
}

class _SidebarBodyState extends State<_SidebarBody> {
  late final Listenable _listenable;

  bool _pinnedCollapsed = false;
  bool _selecting = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _listenable = Listenable.merge(<Listenable>[
      widget.services.conversations,
      widget.services.settings,
      widget.services.memories,
    ]);
    // 首帧结束后刷新一次记忆数量（不阻塞侧栏渲染）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.services.memories.refresh();
    });
  }

  // ---------------------------------------------------------------------------
  // 入口动作
  // ---------------------------------------------------------------------------

  /// 先关闭抽屉再执行导航，避免设置/记忆页被抽屉盖住。
  void _openEntry(VoidCallback action) {
    final close = widget.onClose;
    if (close != null) close();
    action();
  }

  Future<void> _openConversation(String id) async {
    await widget.services.conversations.openConversation(id);
    if (!mounted) return;
    widget.onClose?.call();
  }

  Future<void> _openUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('打开链接失败：$error')));
    }
  }

  Future<void> _showAbout() async {
    final colors = context.colors;
    await showSoftDialog<void>(
      context: context,
      title: '关于 DeepSleep',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '版本 v${AppInfo.version}',
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            '${AppInfo.appName}（${AppInfo.appNameCn}）以 MIT 许可证开源。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '免责声明：${AppInfo.disclaimer}。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _openUrl(AppInfo.repoUrl),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                children: <Widget>[
                  Text(
                    'GitHub 仓库',
                    style: TextStyle(fontSize: 14, color: colors.brandText),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: colors.brandText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  void _handleProfileAction(_ProfileAction action) {
    switch (action) {
      case _ProfileAction.switchProfile:
        _showProfileSheet();
        break;
      case _ProfileAction.memory:
        _openMemoryCenter();
        break;
      case _ProfileAction.settings:
        _openEntry(widget.onOpenSettings);
        break;
      case _ProfileAction.about:
        _showAbout();
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 多选
  // ---------------------------------------------------------------------------

  void _startSelecting(Conversation conversation) {
    setState(() {
      _selecting = true;
      _selectedIds
        ..clear()
        ..add(conversation.id);
    });
  }

  void _cancelSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showSoftConfirm(
      context: context,
      title: '删除对话',
      description: '删除后不可恢复。\n\n已选择 $count 个对话。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await widget.services.conversations.deleteConversation(id);
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // 会话条目操作
  // ---------------------------------------------------------------------------

  Future<void> _handleAction(
    Conversation conversation,
    _ConvAction action,
  ) async {
    switch (action) {
      case _ConvAction.rename:
        await _rename(conversation);
        break;
      case _ConvAction.pin:
        await widget.services.conversations.togglePin(conversation.id);
        break;
      case _ConvAction.export:
        await _exportMarkdown(conversation);
        break;
      case _ConvAction.select:
        _startSelecting(conversation);
        break;
      case _ConvAction.delete:
        await _delete(conversation);
        break;
    }
  }

  Future<void> _rename(Conversation conversation) async {
    final result = await showSoftInputDialog(
      context: context,
      title: '重命名对话',
      initialValue: conversation.title,
      hintText: '输入新的对话标题',
      confirmLabel: '保存',
    );
    final title = result?.trim() ?? '';
    if (title.isEmpty) return;
    await widget.services.conversations.renameConversation(
      conversation.id,
      title,
    );
  }

  Future<void> _exportMarkdown(Conversation conversation) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final messages =
          await widget.services.database.listMessages(conversation.id);
      final markdown = widget.services.exports.conversationToMarkdown(
        conversation,
        messages,
      );
      await widget.services.exports.shareTextFile(
        fileName: 'deepsleep-${fileTimestamp(DateTime.now())}.md',
        content: markdown,
        mimeType: 'text/markdown',
      );
    } catch (error) {
      final message =
          error is ApiException ? error.friendlyMessage : '导出失败：$error';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _delete(Conversation conversation) async {
    final confirmed = await showSoftConfirm(
      context: context,
      title: '删除对话',
      description: '删除后不可恢复。\n\n「${conversation.title}」将被永久删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    await widget.services.conversations.deleteConversation(conversation.id);
  }

  // ---------------------------------------------------------------------------
  // 用户档案
  // ---------------------------------------------------------------------------

  Future<void> _showProfileSheet() async {
    final settings = widget.services.settings;
    await showSoftSheet<void>(
      context: context,
      title: '切换用户档案',
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final colors = context.colors;
          final profiles = settings.profiles;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '每个档案拥有独立的对话与长期记忆',
                style: TextStyle(fontSize: 12.5, color: colors.textTertiary),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final profile in profiles)
                      _buildProfileTile(context, profile),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      title: Text(
                        '新增档案',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textPrimary,
                        ),
                      ),
                      onTap: () => _createProfile(context),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileTile(BuildContext sheetContext, UserProfile profile) {
    final colors = context.colors;
    final isActive =
        widget.services.settings.settings.activeProfileId == profile.id;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(profile.emoji, style: const TextStyle(fontSize: 20)),
      title: Text(
        profile.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          color: isActive ? colors.brandText : colors.textPrimary,
        ),
      ),
      subtitle: profile.persona.trim().isEmpty
          ? null
          : Text(
              profile.persona.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
            ),
      trailing: isActive
          ? Icon(Icons.check_rounded, size: 16, color: colors.textSecondary)
          : null,
      onTap: () => _switchProfile(sheetContext, profile),
    );
  }

  Future<void> _switchProfile(
    BuildContext sheetContext,
    UserProfile profile,
  ) async {
    final services = widget.services;
    await services.settings.switchProfile(profile.id);
    await services.conversations.reloadForProfile();
    await services.memories.refresh();
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    if (!mounted) return;
    widget.onClose?.call();
  }

  Future<void> _createProfile(BuildContext sheetContext) async {
    final draft = await showSoftDialog<_ProfileDraft>(
      context: sheetContext,
      title: '新增用户档案',
      child: const _ProfileDraftForm(),
    );
    if (draft == null) return;
    final services = widget.services;
    final created = await services.settings.createProfile(
      name: draft.name,
      emoji: draft.emoji,
      persona: draft.persona,
    );
    await services.settings.switchProfile(created.id);
    await services.conversations.reloadForProfile();
    await services.memories.refresh();
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    if (!mounted) return;
    widget.onClose?.call();
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgSidebar,
        border: Border(
          right: BorderSide(color: colors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: ListenableBuilder(
        listenable: _listenable,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildSearchEntry(context),
              const SizedBox(height: 8),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1,
                      child: child,
                    ),
                  ),
                  child: _selecting
                      ? _buildSelectionBar(context)
                      : const SizedBox(width: double.infinity),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: KeyedSubtree(
                    key: ValueKey<bool>(_selecting),
                    child: _buildConversationList(context),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.border),
              _buildProfileBar(context),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSearch() async {
    final close = widget.onClose;
    if (close != null) close();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GlobalSearchPage(services: widget.services),
      ),
    );
  }

  Widget _buildSearchEntry(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.bgHover,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openSearch,
        child: SizedBox(
          height: 44,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 12),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                '搜索对话内容…',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.bgHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '已选 ${_selectedIds.length} 项',
            style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
          ),
          const Spacer(),
          TextButton(
            onPressed: _cancelSelecting,
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('取消', style: TextStyle(fontSize: 13.5)),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
            style: TextButton.styleFrom(
              foregroundColor: colors.danger,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('删除', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(BuildContext context) {
    final all = widget.services.conversations.conversations;
    if (all.isEmpty) {
      return _buildEmptyState(context);
    }

    final pinned = all.where((c) => c.pinned).toList(growable: false);
    final normal = all.where((c) => !c.pinned).toList(growable: false);

    final children = <Widget>[];
    if (pinned.isNotEmpty) {
      children.add(_buildPinnedHeader(context));
      if (!_pinnedCollapsed) {
        for (final conversation in pinned) {
          children.add(_buildRow(context, conversation));
        }
      }
    }

    final now = DateTime.now();
    final grouped = <String, List<Conversation>>{};
    for (final conversation in normal) {
      final label = _groupLabel(conversation.updatedAt, now);
      grouped.putIfAbsent(label, () => <Conversation>[]).add(conversation);
    }
    var isFirstGroup = true;
    for (final label in const <String>['今天', '昨天', '更早']) {
      final group = grouped[label];
      if (group == null || group.isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(
            top: isFirstGroup && pinned.isEmpty ? 0 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildSectionHeader(context, label),
              for (final conversation in group)
                _buildRow(context, conversation),
            ],
          ),
        ),
      );
      isFirstGroup = false;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: children,
    );
  }

  String _groupLabel(DateTime time, DateTime now) {
    final label = conversationGroupLabel(time, now: now);
    if (label == '今天' || label == '昨天') return label;
    return '更早';
  }

  Widget _buildPinnedHeader(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '置顶',
              style: TextStyle(
                fontSize: 11.5,
                height: 18 / 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
              ),
            ),
          ),
          IconButton(
            tooltip: _pinnedCollapsed ? '展开置顶' : '折叠置顶',
            onPressed: () =>
                setState(() => _pinnedCollapsed = !_pinnedCollapsed),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            iconSize: 16,
            icon: Icon(
              _pinnedCollapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          height: 18 / 11.5,
          fontWeight: FontWeight.w500,
          color: context.colors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, Conversation conversation) {
    return _ConversationRow(
      conversation: conversation,
      active: widget.services.conversations.activeId == conversation.id,
      selecting: _selecting,
      selected: _selectedIds.contains(conversation.id),
      onTap: () {
        if (_selecting) {
          _toggleSelected(conversation.id);
        } else {
          _openConversation(conversation.id);
        }
      },
      onAction: (action) => _handleAction(conversation, action),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '还没有对话',
              style: TextStyle(fontSize: 14, color: colors.textTertiary),
            ),
            const SizedBox(height: 4),
            Text(
              '点顶栏「+」开始第一次聊天',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Offset _anchorOf(BuildContext anchorContext) {
    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return Offset.zero;
    }
    return renderObject.localToGlobal(
      renderObject.size.bottomRight(Offset.zero),
    );
  }

  Future<void> _showProfileMenu(BuildContext anchorContext) async {
    final action = await showSoftMenu<_ProfileAction>(
      context: context,
      anchor: _anchorOf(anchorContext),
      items: const <SoftMenuItem<_ProfileAction>>[
        SoftMenuItem<_ProfileAction>(
          value: _ProfileAction.switchProfile,
          icon: Icons.people_outline,
          label: '切换档案',
        ),
        SoftMenuItem<_ProfileAction>(
          value: _ProfileAction.memory,
          icon: Icons.psychology_outlined,
          label: '记忆中心',
        ),
        SoftMenuItem<_ProfileAction>(
          value: _ProfileAction.settings,
          icon: Icons.settings_outlined,
          label: '设置',
        ),
        SoftMenuItem<_ProfileAction>(
          value: _ProfileAction.about,
          icon: Icons.info_outline,
          label: '关于',
        ),
      ],
    );
    if (action == null) return;
    _handleProfileAction(action);
  }

  Widget _buildProfileBar(BuildContext context) {
    final colors = context.colors;
    final profile = widget.services.settings.activeProfile;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Builder(
        builder: (barContext) {
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showProfileMenu(barContext),
            child: SizedBox(
              height: 40,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.brandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      profile.emoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openMemoryCenter() async {
    // 打开前先刷新一次，保证侧栏数量与记忆中心内容同步。
    await widget.services.memories.refresh();
    if (!mounted) return;
    _openEntry(widget.onOpenMemory);
  }
}

// -----------------------------------------------------------------------------
// 会话行（40 高、圆角 10、选中/多选态、右侧更多菜单）
// -----------------------------------------------------------------------------

class _ConversationRow extends StatefulWidget {
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.active,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onAction,
  });

  final Conversation conversation;
  final bool active;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<_ConvAction> onAction;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  bool _hovered = false;

  Offset _anchorOf(BuildContext anchorContext) {
    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return Offset.zero;
    }
    return renderObject.localToGlobal(
      renderObject.size.bottomRight(Offset.zero),
    );
  }

  Future<void> _openMenu(BuildContext anchorContext) async {
    final pinned = widget.conversation.pinned;
    final action = await showSoftMenu<_ConvAction>(
      context: context,
      anchor: _anchorOf(anchorContext),
      items: <SoftMenuItem<_ConvAction>>[
        const SoftMenuItem<_ConvAction>(
          value: _ConvAction.rename,
          icon: Icons.edit_outlined,
          label: '重命名',
        ),
        SoftMenuItem<_ConvAction>(
          value: _ConvAction.pin,
          icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          label: pinned ? '取消置顶' : '置顶',
        ),
        const SoftMenuItem<_ConvAction>(
          value: _ConvAction.export,
          icon: Icons.ios_share_outlined,
          label: '导出 Markdown',
        ),
        const SoftMenuItem<_ConvAction>(
          value: _ConvAction.select,
          icon: Icons.checklist_rounded,
          label: '多选',
        ),
        const SoftMenuItem<_ConvAction>(
          value: _ConvAction.delete,
          icon: Icons.delete_outline_rounded,
          label: '删除',
          destructive: true,
        ),
      ],
    );
    if (action == null) return;
    widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = widget.selected || widget.active
        ? colors.brandSoft
        : (_hovered ? colors.bgHover : Colors.transparent);
    final textColor = widget.active && !widget.selecting
        ? colors.brandText
        : colors.textPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 40,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              onLongPress: () => _openMenu(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: <Widget>[
                    if (widget.selecting) ...<Widget>[
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        child: Icon(
                          widget.selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          key: ValueKey<bool>(widget.selected),
                          size: 18,
                          color: widget.selected
                              ? colors.brand
                              : colors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        widget.conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 22 / 14,
                          color: textColor,
                        ),
                      ),
                    ),
                    if (!widget.selecting)
                      SizedBox(
                        width: 24,
                        height: 22,
                        child: Builder(
                          builder: (buttonContext) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _openMenu(buttonContext),
                              child: Center(
                                child: Icon(
                                  Icons.more_horiz_rounded,
                                  size: 18,
                                  color: colors.textTertiary,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 用户档案编辑对话框
// -----------------------------------------------------------------------------

/// 新建档案时在对话框之间传递的草稿数据。
class _ProfileDraft {
  const _ProfileDraft({
    required this.name,
    required this.emoji,
    required this.persona,
  });

  final String name;
  final String emoji;
  final String persona;
}

class _ProfileDraftForm extends StatefulWidget {
  const _ProfileDraftForm({super.key});

  @override
  State<_ProfileDraftForm> createState() => _ProfileDraftFormState();
}

class _ProfileDraftFormState extends State<_ProfileDraftForm> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emojiController =
      TextEditingController(text: '🧑');
  final TextEditingController _personaController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    _personaController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _ProfileDraft(
        name: name,
        emoji: _emojiController.text.trim().isEmpty
            ? '🧑'
            : _emojiController.text.trim(),
        persona: _personaController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 64,
              child: TextField(
                controller: _emojiController,
                maxLength: 2,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: '头像',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: _nameController,
                maxLength: 20,
                autofocus: true,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: '名字',
                  counterText: '',
                  hintText: '例如：工作号',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _personaController,
          maxLines: 3,
          maxLength: 300,
          style: TextStyle(fontSize: 15, color: colors.textPrimary),
          decoration: const InputDecoration(
            labelText: '人设（可选）',
            hintText: '例如：回答尽量简短，称呼我为「老板」。',
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nameController,
              builder: (context, value, _) {
                return FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _save,
                  child: const Text('保存'),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
