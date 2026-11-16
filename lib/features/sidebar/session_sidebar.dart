/// 会话侧栏：严格对齐 DeepSeek Demo 侧栏规格（docs/UI_SPEC.md §7）。
///
/// 结构：顶部品牌区（48）→ 新建对话（40）→ 搜索 → 分组会话列表 →
/// 当前档案 → 记忆中心 / 设置（底部入口区 64）。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/profile_models.dart';
import '../../services/contracts.dart';
import '../../state/app_services.dart';

// Demo 规格中的固定色（主题令牌未覆盖的部分，深色值单独给出）。
const Color _hoverLight = Color(0xFFF1F3F5);
const Color _hoverDark = Color(0xFF2C2C2E);
const Color _activeLight = Color(0xFFE4EDFD);
const Color _activeDark = Color(0xFF353638);
const Color _newChatDark = Color(0xFF43454A);
const Color _newChatTextDark = Color(0xFFF9FAFB);

// 新建按钮阴影（浅色）：0 -2px 2px rgba(72,104,178,.04)、
// 0 2px 2px rgba(106,111,117,.09)、0 1px 2px rgba(72,104,178,.08)。
const List<BoxShadow> _newChatShadow = <BoxShadow>[
  BoxShadow(color: Color(0x0A4868B2), offset: Offset(0, -2), blurRadius: 2),
  BoxShadow(color: Color(0x176A6F75), offset: Offset(0, 2), blurRadius: 2),
  BoxShadow(color: Color(0x144868B2), offset: Offset(0, 1), blurRadius: 2),
];
const List<BoxShadow> _newChatShadowHover = <BoxShadow>[
  BoxShadow(color: Color(0x0A4868B2), offset: Offset(0, 4), blurRadius: 4),
  BoxShadow(color: Color(0x0A4868B2), offset: Offset(0, -3), blurRadius: 4),
  BoxShadow(color: Color(0x1A6A6F75), offset: Offset(0, 6), blurRadius: 6),
];
// 深色无阴影可用，用近似内高光 + 淡投影替代 inset。
const List<BoxShadow> _newChatShadowDark = <BoxShadow>[
  BoxShadow(color: Color(0x1AFFFFFF), offset: Offset(0, 1), blurRadius: 1),
  BoxShadow(color: Color(0x146A6F75), offset: Offset(0, 2), blurRadius: 4),
];

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
    // 首帧结束后刷新一次记忆数量（不阻塞侧栏渲染）。
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
      case _ConvAction.delete:
        await _delete(conversation);
        break;
    }
  }

  Future<void> _rename(Conversation conversation) async {
    final colors = context.colors;
    final controller = TextEditingController(text: conversation.title);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('重命名对话'),
          content: SizedBox(
            height: 40,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                counterText: '',
                hintText: '输入新的对话标题',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.brand),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.brand),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.brand),
                ),
              ),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
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
    final colors = context.colors;
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
              style: FilledButton.styleFrom(backgroundColor: colors.danger),
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
            final sheetColors = context.colors;
            final profiles = settings.profiles;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      '切换用户档案',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: sheetColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '每个档案拥有独立的对话与长期记忆',
                      style: TextStyle(
                        fontSize: 12,
                        color: sheetColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: <Widget>[
                          for (final profile in profiles)
                            _buildProfileTile(sheetContext, profile),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.add,
                              size: 18,
                              color: sheetColors.textSecondary,
                            ),
                            title: Text(
                              '新增档案',
                              style: TextStyle(
                                fontSize: 14,
                                color: sheetColors.textPrimary,
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
          ? Icon(Icons.check, size: 16, color: colors.textSecondary)
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
      decoration: BoxDecoration(
        color: colors.bgSidebar,
        border: Border(
          right: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: ListenableBuilder(
          listenable: _listenable,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(context),
                _NewChatButton(onTap: _newConversation),
                const SizedBox(height: 12),
                _buildSearchField(context),
                const SizedBox(height: 24),
                Expanded(child: _buildConversationList(context)),
                _buildProfileRow(context),
                const SizedBox(height: 4),
                Divider(height: 1, thickness: 1, color: colors.border),
                SizedBox(
                  height: 64,
                  child: Column(
                    children: <Widget>[
                      _buildBottomEntry(
                        context,
                        leading: Icon(
                          Icons.psychology_outlined,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        label: '记忆中心',
                        trailing: widget.services.memories.stats.active > 0
                            ? '${widget.services.memories.stats.active}'
                            : null,
                        onTap: _openMemoryCenter,
                      ),
                      _buildBottomEntry(
                        context,
                        leading: Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        label: '设置',
                        onTap: () => _openEntry(widget.onOpenSettings),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(4, 15, 0, 10),
      child: Row(
        children: <Widget>[
          Icon(Icons.auto_awesome, size: 22, color: colors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'DeepSleep',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                height: 22 / 20,
                fontWeight: FontWeight.w600,
                color: colors.brand,
              ),
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              tooltip: '关闭侧栏',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              iconSize: 18,
              icon: Icon(Icons.close, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: 14, color: colors.textPrimary),
        cursorHeight: 16,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: isDark ? _hoverDark : _hoverLight,
          hintText: '搜索对话',
          hintStyle: TextStyle(fontSize: 14, color: colors.textTertiary),
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
          suffixIconConstraints: const BoxConstraints(minWidth: 30),
          contentPadding: EdgeInsets.zero,
          border: noBorder,
          enabledBorder: noBorder,
          focusedBorder: noBorder,
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
      padding: EdgeInsets.zero,
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
    var first = true;
    for (final label in labels) {
      final group = grouped[label];
      if (group == null || group.isEmpty) continue;
      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: first ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 18 / 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
              for (final conversation in group)
                _ConversationRow(
                  conversation: conversation,
                  active:
                      widget.services.conversations.activeId == conversation.id,
                  onTap: () => _openConversation(conversation.id),
                  onAction: (action) => _handleAction(conversation, action),
                ),
            ],
          ),
        ),
      );
      first = false;
    }
    return widgets;
  }

  Widget _buildEmptyState(BuildContext context, {required bool hasSearch}) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              hasSearch ? '没有找到匹配的对话' : '还没有对话',
              style: TextStyle(fontSize: 14, color: colors.textTertiary),
            ),
            if (!hasSearch) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '点上方「开启新对话」开始第一次聊天',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(BuildContext context) {
    final profile = widget.services.settings.activeProfile;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _BottomRow(
        height: 32,
        onTap: _showProfileSheet,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 18,
              child: Center(
                child: Text(
                  profile.emoji,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMemoryCenter() async {
    // 打开前先刷新一次，保证侧栏数量与记忆中心内容同步。
    await widget.services.memories.refresh();
    if (!mounted) return;
    _openEntry(widget.onOpenMemory);
  }

  Widget _buildBottomEntry(
    BuildContext context, {
    required Widget leading,
    required String label,
    String? trailing,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return _BottomRow(
      height: 32,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          SizedBox(width: 18, child: Center(child: leading)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(fontSize: 11, color: colors.textTertiary),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 新建对话按钮（40 高、胶囊、带 Demo 阴影与 hover 阴影）
// -----------------------------------------------------------------------------

class _NewChatButton extends StatefulWidget {
  const _NewChatButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<_NewChatButton> createState() => _NewChatButtonState();
}

class _NewChatButtonState extends State<_NewChatButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final background = isDark ? _newChatDark : colors.bgBase;
    final foreground =
        isDark ? _newChatTextDark : colors.textPrimary;
    final shadows = isDark
        ? _newChatShadowDark
        : (_hovered ? _newChatShadowHover : _newChatShadow);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: 40,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(100),
            boxShadow: shadows,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            child: InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.add, size: 16, color: foreground),
                    const SizedBox(width: 6),
                    Text(
                      '开启新对话',
                      style: TextStyle(
                        fontSize: 14,
                        height: 22 / 14,
                        fontWeight: FontWeight.w500,
                        color: foreground,
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
// 底部入口行（32 高、hover 态）
// -----------------------------------------------------------------------------

class _BottomRow extends StatefulWidget {
  const _BottomRow({
    super.key,
    required this.child,
    required this.onTap,
    this.height = 32,
  });

  final Widget child;
  final VoidCallback onTap;
  final double height;

  @override
  State<_BottomRow> createState() => _BottomRowState();
}

class _BottomRowState extends State<_BottomRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: widget.height,
        child: Material(
          color: _hovered
              ? (isDark ? _hoverDark : _hoverLight)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 会话行（40 高、圆角 12、hover/选中态、长按或 hover 显示菜单按钮）
// -----------------------------------------------------------------------------

class _ConversationRow extends StatefulWidget {
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.active,
    required this.onTap,
    required this.onAction,
  });

  final Conversation conversation;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<_ConvAction> onAction;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  final GlobalKey<PopupMenuButtonState<_ConvAction>> _menuKey =
      GlobalKey<PopupMenuButtonState<_ConvAction>>();
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final showMore = _hovered || widget.active;

    final background = widget.active
        ? (isDark ? _activeDark : _activeLight)
        : (_hovered ? (isDark ? _hoverDark : _hoverLight) : Colors.transparent);
    final textColor = widget.active
        ? (isDark ? Colors.white : colors.brandText)
        : colors.textPrimary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          height: 40,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              onLongPress: () => _menuKey.currentState?.showButtonMenu(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                child: Row(
                  children: <Widget>[
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
                    const SizedBox(width: 4),
                    Visibility(
                      visible: showMore,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: SizedBox(
                        width: 26,
                        height: 22,
                        child: PopupMenuButton<_ConvAction>(
                        key: _menuKey,
                        tooltip: '更多操作',
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        icon: Icon(
                          Icons.more_horiz,
                          color: widget.active
                              ? textColor
                              : colors.textTertiary,
                        ),
                        onSelected: widget.onAction,
                        itemBuilder: (menuContext) =>
                            <PopupMenuEntry<_ConvAction>>[
                          const PopupMenuItem<_ConvAction>(
                            value: _ConvAction.rename,
                            child: Text('重命名'),
                          ),
                          PopupMenuItem<_ConvAction>(
                            value: _ConvAction.pin,
                            child: Text(
                              widget.conversation.pinned ? '取消置顶' : '置顶',
                            ),
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
                const SizedBox(width: 12),
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
            const SizedBox(height: 8),
            TextField(
              controller: _personaController,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: '人设（可选）',
                hintText: '例如：回答尽量简短，称呼我为「老板」。',
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
