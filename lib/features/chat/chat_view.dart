/// 聊天主界面：顶栏、未配置提示、消息列表 / 欢迎页、输入区与自动滚动。
///
/// 所有聊天行为都委托给 [ConversationController]；本文件只负责布局与交互。
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/chat_models.dart';
import '../../state/app_services.dart';
import '../../state/conversation_controller.dart';
import '../../state/settings_controller.dart';
import 'widgets/composer.dart';
import 'widgets/context_token_bar.dart';
import 'widgets/message_list.dart';
import 'widgets/streaming_indicator.dart';
import 'widgets/welcome_view.dart';

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.services,
    this.showSidebarButton = true,
    this.onOpenSidebar,
    required this.onOpenSettings,
    required this.onOpenMemory,
  });

  final AppServices services;
  final bool showSidebarButton;
  final VoidCallback? onOpenSidebar;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMemory;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late ConversationController _conversations;
  late SettingsController _settings;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  int _lastMessageCount = 0;
  String? _lastConversationId;
  bool _stickToBottom = true;
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _conversations = widget.services.conversations;
    _settings = widget.services.settings;
    _conversations.addListener(_handleChatChanged);
    _settings.addListener(_handleSettingsChanged);
    _scrollController.addListener(_handleScroll);
    _lastMessageCount = _conversations.messages.length;
    _lastConversationId = _conversations.activeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleChatChanged();
      _scrollToBottom(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services) {
      _conversations.removeListener(_handleChatChanged);
      _settings.removeListener(_handleSettingsChanged);
      _conversations = widget.services.conversations;
      _settings = widget.services.settings;
      _conversations.addListener(_handleChatChanged);
      _settings.addListener(_handleSettingsChanged);
      _lastMessageCount = _conversations.messages.length;
      _lastConversationId = _conversations.activeId;
    }
  }

  @override
  void dispose() {
    _conversations.removeListener(_handleChatChanged);
    _settings.removeListener(_handleSettingsChanged);
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleChatChanged() {
    if (!mounted) return;
    final controller = _conversations;
    final messages = controller.messages;
    final activeId = controller.activeId;
    final conversationChanged = activeId != _lastConversationId;
    final grew = messages.length > _lastMessageCount;
    final lastRole = messages.isEmpty ? null : messages.last.role;
    final forceStick = conversationChanged ||
        (grew && (lastRole == MessageRole.user || controller.streaming));
    if (forceStick) _stickToBottom = true;
    _lastConversationId = activeId;
    _lastMessageCount = messages.length;

    final notice = controller.notice;
    if (notice != null && notice.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentNotice(notice));
    }

    setState(() {});

    final streaming = controller.streaming;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_stickToBottom) {
        _scrollToBottom(animate: !streaming);
      } else {
        _syncAtBottom();
      }
    });
  }

  void _presentNotice(String notice) {
    if (!mounted) return;
    if (_conversations.notice != notice) return;
    _conversations.consumeNotice();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(notice),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleScroll() {
    final atBottom = _computeAtBottom();
    _stickToBottom = atBottom;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
    }
  }

  bool _computeAtBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return true;
    return position.maxScrollExtent - position.pixels < 80;
  }

  void _syncAtBottom() {
    final atBottom = _computeAtBottom();
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
    if (!_atBottom) {
      setState(() => _atBottom = true);
    }
  }

  void _fillInput(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.collapsed(offset: text.length);
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final controller = _conversations;
    final messages = controller.messages;
    final activeConversation = controller.activeConversation;
    final hasApiKey = _settings.hasApiKey;
    final showTokenBar = _settings.settings.showTokenUsage &&
        (controller.contextTokens > 0 ||
            controller.compressing ||
            (activeConversation?.summary.trim().isNotEmpty ?? false));

    return Container(
      color: colors.bgBase,
      child: Column(
        children: <Widget>[
          _ChatHeader(
            controller: controller,
            showSidebarButton: widget.showSidebarButton,
            onOpenSidebar: widget.onOpenSidebar,
            onOpenSettings: widget.onOpenSettings,
            onOpenMemory: widget.onOpenMemory,
          ),
          if (!hasApiKey) _ApiKeyBanner(onTap: widget.onOpenSettings),
          Expanded(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? WelcomeView(
                        onPickSuggestion: _fillInput,
                        hasApiKey: hasApiKey,
                        onOpenSettings: widget.onOpenSettings,
                      )
                    : Stack(
                        children: <Widget>[
                          MessageList(
                            controller: controller,
                            scrollController: _scrollController,
                          ),
                          if (!_atBottom)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 8,
                              child: Center(
                                child: _BackToBottomButton(
                                  onTap: () {
                                    _stickToBottom = true;
                                    _scrollToBottom();
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
          if (controller.streaming && messages.isNotEmpty)
            StreamingIndicatorBar(onStop: controller.stop),
          if (showTokenBar)
            ContextTokenBar(
              tokens: controller.contextTokens,
              compressing: controller.compressing,
              hasSummary:
                  activeConversation?.summary.trim().isNotEmpty ?? false,
            ),
          Composer(
            controller: controller,
            settings: _settings,
            textController: _inputController,
            focusNode: _inputFocus,
            onOpenSettings: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.controller,
    required this.showSidebarButton,
    required this.onOpenSidebar,
    required this.onOpenSettings,
    required this.onOpenMemory,
  });

  final ConversationController controller;
  final bool showSidebarButton;
  final VoidCallback? onOpenSidebar;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMemory;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = controller.activeConversation?.title ?? AppInfo.appName;
    final memoryCount = controller.lastMemory.items.length;
    final sidebarAction = onOpenSidebar;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.bgBase,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: <Widget>[
          if (showSidebarButton)
            _HeaderIconButton(
              icon: Icons.menu_rounded,
              tooltip: '会话列表',
              onTap: sidebarAction,
            )
          else
            const SizedBox(width: 8),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          _MemoryButton(count: memoryCount, onTap: onOpenMemory),
          _HeaderIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: '新建对话',
            onTap: () {
              controller.createConversation();
            },
          ),
          _HeaderIconButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            onTap: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: colors.textSecondary),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    );
  }
}

class _MemoryButton extends StatelessWidget {
  const _MemoryButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: '记忆中心',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            isLabelVisible: count > 0,
            backgroundColor: colors.brand,
            textColor: Colors.white,
            label: Text('$count'),
            child: Icon(
              Icons.psychology_alt,
              size: 21,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiKeyBanner extends StatelessWidget {
  const _ApiKeyBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.brandSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: colors.brand.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.key_off_outlined,
                size: 16,
                color: colors.brandText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '尚未配置 DeepSeek API Key，点此前往设置',
                  style: TextStyle(fontSize: 12.5, color: colors.brandText),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.brandText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackToBottomButton extends StatelessWidget {
  const _BackToBottomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.bgElevated,
      elevation: 2,
      shape: StadiumBorder(side: BorderSide(color: colors.border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.arrow_downward_rounded,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '回到底部',
                style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
