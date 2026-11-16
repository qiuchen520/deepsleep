/// 聊天主界面：顶栏、消息列表 / 欢迎页、输入区与自动滚动。
///
/// 视觉基调：极简、安静、留白多（参考 DeepSeek 官方 App/Web）。
/// 所有聊天行为都委托给 [ConversationController]；本文件只负责布局与交互。
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/chat_models.dart';
import '../../services/voice_service.dart';
import '../../state/app_services.dart';
import '../../state/conversation_controller.dart';
import '../../state/settings_controller.dart';
import 'widgets/composer.dart';
import 'widgets/context_token_bar.dart';
import 'widgets/message_list.dart';
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
  String? _lastFocusId;
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
      _detectModels();
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

  Future<void> _detectModels() async {
    if (!_settings.hasApiKey) return;
    try {
      final models = await widget.services.api.listModels();
      if (models.isNotEmpty) {
        await _settings.setAvailableModels(models);
      }
    } catch (_) {
      // 自动检测失败不打扰用户，打开选择面板时可手动重试。
    }
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    if (!_conversations.streaming &&
        _conversations.deepThinking != _settings.settings.deepThinking) {
      _conversations.setDeepThinking(_settings.settings.deepThinking);
    }
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

    final focusId = controller.focusedMessageId;
    if (focusId != null && focusId != _lastFocusId) {
      _lastFocusId = focusId;
      final idx = messages.indexWhere((m) => m.id == focusId);
      if (idx >= 0) {
        _stickToBottom = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final position = _scrollController.position;
          final ratio = messages.isEmpty ? 0.0 : idx / messages.length;
          final target = (position.maxScrollExtent * ratio)
              .clamp(0.0, position.maxScrollExtent);
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        });
        Future<void>.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) controller.clearFocusMessage();
        });
      }
    } else if (focusId == null) {
      _lastFocusId = null;
    }

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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final controller = _conversations;
    final messages = controller.messages;
    final hasApiKey = _settings.hasApiKey;

    return Container(
      color: colors.bgBase,
      child: Column(
        children: <Widget>[
          _ChatHeader(
            controller: controller,
            showSidebarButton: widget.showSidebarButton,
            onOpenSidebar: widget.onOpenSidebar,
          ),
          if (!hasApiKey) _ApiKeyHint(onTap: widget.onOpenSettings),
          Expanded(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const WelcomeView()
                    : Stack(
                        children: <Widget>[
                          MessageList(
                            controller: controller,
                            scrollController: _scrollController,
                          ),
                          if (!_atBottom)
                            Positioned(
                              right: 16,
                              bottom: 12,
                              child: _BackToBottomButton(
                                onTap: () {
                                  _stickToBottom = true;
                                  _scrollToBottom();
                                },
                              ),
                            ),
                        ],
                      ),
          ),
          if (controller.compressing) const ContextTokenBar(),
          Container(
            height: 16,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  colors.bgBase.withValues(alpha: 0),
                  colors.bgBase,
                ],
              ),
            ),
          ),
          Composer(
            controller: controller,
            settings: _settings,
            services: widget.services,
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
  });

  final ConversationController controller;
  final bool showSidebarButton;
  final VoidCallback? onOpenSidebar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = controller.activeConversation?.title ?? AppInfo.appName;
    return SizedBox(
      height: 60,
      child: Row(
        children: <Widget>[
          if (showSidebarButton)
            _HeaderIconButton(
              icon: Icons.menu_rounded,
              tooltip: '会话列表',
              onTap: onOpenSidebar,
            )
          else
            const SizedBox(width: 14),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 24 / 16,
                color: colors.textPrimary,
              ),
            ),
          ),
          _HeaderIconButton(
            icon: VoiceService.instance.isSpeaking
                ? Icons.volume_up_rounded
                : Icons.volume_up_outlined,
            tooltip: '朗读上一条回答',
            onTap: () async {
              final voice = VoiceService.instance;
              if (voice.isSpeaking) {
                await voice.stopSpeaking();
              } else {
                final text = controller.lastAssistantMessage?.displayContent;
                if (text == null || text.trim().isEmpty) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('还没有可朗读的回答')),
                    );
                  return;
                }
                await voice.speak(text);
              }
            },
          ),
          _HeaderIconButton(
            icon: Icons.add_circle_outline_rounded,
            tooltip: '新建对话',
            onTap: () => controller.createConversation(),
          ),
          const SizedBox(width: 6),
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
      icon: Icon(icon, size: 24, color: colors.textSecondary),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 46, height: 46),
    );
  }
}

class _ApiKeyHint extends StatelessWidget {
  const _ApiKeyHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '未配置 DeepSeek API Key',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
            const SizedBox(width: 6),
            Text(
              '前往设置',
              style: TextStyle(fontSize: 12, color: colors.brandText),
            ),
          ],
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
      elevation: 1,
      shadowColor: colors.shadow,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.arrow_downward_rounded,
            size: 16,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
