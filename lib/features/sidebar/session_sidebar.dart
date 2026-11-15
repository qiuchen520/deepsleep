/// 会话侧栏：品牌头部、新建对话、会话搜索、按时间分组的会话列表，
/// 以及底部的用户档案切换 / 记忆中心 / 设置入口。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/profile_models.dart';
import '../../services/contracts.dart';
import '../../state/app_services.dart';

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
enum _ConvAction { rename, pin, export, delete }

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
  final TextEditingController _searchController = TextEditingController();
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();
    _listenable = Listenable.merge(<Listenable>[
      widget.services.conversations,
      widget.services.settings,
      widget.services.memories,
    ]);
    // 首帧结束后刷新一次记忆数量徽标（不阻塞侧栏渲染）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.services.memories.refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _newConversation() async {
    await widget.services.conversations.createConversation();
    if (!mounted) return;
    widget.onClose?.call();
  }

  Future<void> _openConversation(String id) async {
    await widget.services.conversations.openConversation(id);
    if (!mounted) return;
    widget.onClose?.call();
  }

  // ---------------------------------------------------------------------------
  // 会话条目操作
  // ---------------------------------------------------------------------------

  Future<void> _handleAction(Conversation conversation, _ConvAction action) async {
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
      case _ConvAction.delete:
        await _delete(conversation);
        break;
    }
  }

  Future<void> _rename(Conversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('重命名对话'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(hintText: '输入新的对话标题'),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除对话'),
          content: Text('删除后不可恢复。\n\n「${conversation.title}」将被永久删除。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.danger,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await widget.services.conversations.deleteConversation(conversation.id);
  }

  // ---------------------------------------------------------------------------
  // 用户档案
  // ---------------------------------------------------------------------------

  Future<void> _showProfileSheet() async {
    final settings = widget.services.settings;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            final profiles = settings.profiles;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      '切换用户档案',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ).copyWith(color: context.colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '每个档案拥有独立的对话与长期记忆',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: <Widget>[
                          for (final profile in profiles)
                            _buildProfileTile(sheetContext, profile),
                          const SizedBox(height: AppSpacing.xs),
                          ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            leading: Icon(
                              Icons.add_circle_outline,
                              color: context.colors.brand,
                            ),
                            title: Text(
                              '新增档案',
                              style: TextStyle(
                                fontSize: 14,
                                color: context.colors.brandText,
                              ),
                            ),
                            onTap: () => _createProfile(sheetContext),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileTile(BuildContext sheetContext, UserProfile profile) {
    final colors = context.colors;
    final isActive =
        widget.services.settings.settings.activeProfileId == profile.id;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      selected: isActive,
      selectedTileColor: colors.brandSoft,
      leading: Text(profile.emoji, style: const TextStyle(fontSize: 22)),
      title: Text(
        profile.name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      subtitle: Text(
        profile.persona.trim().isEmpty ? '未设置人设' : profile.persona.trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
      ),
      trailing: isActive
          ? Icon(Icons.check_circle, size: 18, color: colors.brand)
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
    final draft = await showDialog<_ProfileDraft>(
      context: sheetContext,
      builder: (_) => const _ProfileDraftDialog(title: '新增用户档案'),
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
      color: colors.bgSidebar,
      child: ListenableBuilder(
        listenable: _listenable,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildNewConversationButton(context),
                    const SizedBox(height: AppSpacing.sm),
                    _buildSearchField(context),
                  ],
                ),
              ),
              Expanded(child: _buildConversationList(context)),
              _buildFooter(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  colors.brand,
                  colors.brand.withValues(alpha: 0.72),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 17,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'DeepSleep',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              tooltip: '关闭侧栏',
              iconSize: 20,
              icon: Icon(Icons.close, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildNewConversationButton(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 40,
      child: FilledButton.icon(
        onPressed: _newConversation,
        style: FilledButton.styleFrom(
          backgroundColor: colors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        icon: const Icon(Icons.add, size: 18),
        label: const Text(
          '新建对话',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: 13, color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.bgBase,
          hintText: '搜索对话',
          hintStyle: TextStyle(fontSize: 13, color: colors.textTertiary),
          prefixIcon: Icon(Icons.search, size: 16, color: colors.textTertiary),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  iconSize: 15,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '清除搜索',
                  icon: Icon(Icons.close, color: colors.textTertiary),
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: colors.brand, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final all = widget.services.conversations.conversations;
    final filtered = query.isEmpty
        ? all
        : all
            .where((conversation) =>
                conversation.title.toLowerCase().contains(query))
            .toList(growable: false);

    if (filtered.isEmpty) {
      return _buildEmptyState(context, hasSearch: query.isNotEmpty);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      children: _buildGroups(context, filtered),
    );
  }

  List<Widget> _buildGroups(
    BuildContext context,
    List<Conversation> conversations,
  ) {
    const labels = <String>['今天', '昨天', '7 天内', '30 天内', '更早'];
    final now = DateTime.now();
    final grouped = <String, List<Conversation>>{};
    for (final conversation in conversations) {
      final label = conversationGroupLabel(conversation.updatedAt, now: now);
      grouped.putIfAbsent(label, () => <Conversation>[]).add(conversation);
    }

    final widgets = <Widget>[];
    for (final label in labels) {
      final group = grouped[label];
      if (group == null || group.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: context.colors.textTertiary,
            ),
          ),
        ),
      );
      for (final conversation in group) {
        widgets.add(_buildConversationTile(context, conversation));
      }
    }
    return widgets;
  }

  Widget _buildConversationTile(
    BuildContext context,
    Conversation conversation,
  ) {
    final colors = context.colors;
    final active =
        widget.services.conversations.activeId == conversation.id;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      child: Material(
        color: active ? colors.bgActive : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => _openConversation(conversation.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (conversation.pinned)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.push_pin,
                                size: 11,
                                color: colors.textTertiary,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.3,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: active
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatRelative(conversation.updatedAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_ConvAction>(
                  tooltip: '更多操作',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(Icons.more_horiz, color: colors.textTertiary),
                  onSelected: (action) => _handleAction(conversation, action),
                  itemBuilder: (menuContext) => <PopupMenuEntry<_ConvAction>>[
                    const PopupMenuItem<_ConvAction>(
                      value: _ConvAction.rename,
                      child: Text('重命名'),
                    ),
                    PopupMenuItem<_ConvAction>(
                      value: _ConvAction.pin,
                      child: Text(conversation.pinned ? '取消置顶' : '置顶'),
                    ),
                    const PopupMenuItem<_ConvAction>(
                      value: _ConvAction.export,
                      child: Text('导出 Markdown'),
                    ),
                    const PopupMenuItem<_ConvAction>(
                      value: _ConvAction.delete,
                      child: Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool hasSearch}) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              hasSearch ? Icons.search_off : Icons.chat_bubble_outline,
              size: 34,
              color: colors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasSearch ? '没有找到匹配的对话' : '还没有对话',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hasSearch ? '换个关键词试试' : '点上面的「新建对话」开始第一次聊天吧',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colors = context.colors;
    final profile = widget.services.settings.activeProfile;
    final memoryCount = widget.services.memories.stats.active;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildFooterTile(
            context,
            leading: Text(profile.emoji, style: const TextStyle(fontSize: 18)),
            title: profile.name,
            subtitle: '当前用户档案',
            onTap: _showProfileSheet,
          ),
          _buildFooterTile(
            context,
            leading: Icon(
              Icons.psychology_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
            title: '记忆中心',
            badge: memoryCount,
            onTap: _openMemoryCenter,
          ),
          _buildFooterTile(
            context,
            leading: Icon(
              Icons.settings_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
            title: '设置',
            onTap: () => _openEntry(widget.onOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _openMemoryCenter() async {
    // 打开前先刷新一次，保证侧栏徽标与记忆中心内容同步。
    await widget.services.memories.refresh();
    if (!mounted) return;
    _openEntry(widget.onOpenMemory);
  }

  Widget _buildFooterTile(
    BuildContext context, {
    required Widget leading,
    required String title,
    String? subtitle,
    int? badge,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 24,
                child: Center(child: leading),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              if (badge != null && badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.brandSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    badge > 999 ? '999+' : '$badge',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colors.brandText,
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
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

class _ProfileDraftDialog extends StatefulWidget {
  const _ProfileDraftDialog({
    super.key,
    required this.title,
    this.initialName = '',
    this.initialEmoji = '🧑',
    this.initialPersona = '',
  });

  final String title;
  final String initialName;
  final String initialEmoji;
  final String initialPersona;

  @override
  State<_ProfileDraftDialog> createState() => _ProfileDraftDialogState();
}

class _ProfileDraftDialogState extends State<_ProfileDraftDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _emojiController =
      TextEditingController(text: widget.initialEmoji);
  late final TextEditingController _personaController =
      TextEditingController(text: widget.initialPersona);

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    _personaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
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
              decoration: const InputDecoration(
                labelText: '人设（可选）',
                hintText: '例如：请用简洁专业的中文回答，称呼我为「老板」。',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nameController,
          builder: (context, value, _) {
            final name = value.text.trim();
            return FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                        _ProfileDraft(
                          name: name,
                          emoji: _emojiController.text.trim().isEmpty
                              ? '🧑'
                              : _emojiController.text.trim(),
                          persona: _personaController.text.trim(),
                        ),
                      ),
              child: const Text('保存'),
            );
          },
        ),
      ],
    );
  }
}
