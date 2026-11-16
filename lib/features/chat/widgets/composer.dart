/// 输入区：单层圆角容器（无边框无阴影）、多行输入、附件 / 深度思考 / 联网搜索、
/// 发送 / 停止与免责声明。
library;

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/profile_models.dart';
import '../../../state/conversation_controller.dart';
import '../../../state/settings_controller.dart';
import 'attachment_preview.dart';

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.settings,
    required this.textController,
    required this.focusNode,
    required this.onOpenSettings,
  });

  final ConversationController controller;
  final SettingsController settings;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onOpenSettings;

  bool get _searchConfigured {
    final appSettings = settings.settings;
    switch (appSettings.searchBackend) {
      case SearchBackend.off:
        return false;
      case SearchBackend.deepseek:
        // DeepSeek 内置搜索不需要单独的搜索服务 Key。
        return true;
      case SearchBackend.tavily:
      case SearchBackend.serper:
        return settings.searchApiKey.trim().isNotEmpty;
    }
  }

  void _send() {
    if (controller.streaming) return;
    final text = textController.text;
    if (text.trim().isEmpty && controller.pendingAttachments.isEmpty) return;
    focusNode.requestFocus();
    textController.clear();
    controller.sendMessage(text);
  }

  void _stop() {
    controller.stop();
  }

  void _toggleSearch(BuildContext context) {
    if (!_searchConfigured) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('请在设置中选择搜索方式或填写搜索 API Key'),
          action: SnackBarAction(
            label: '前往设置',
            onPressed: onOpenSettings,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    controller.setSearchEnabled(!controller.searchOn);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appSettings = settings.settings;
    final pending = controller.pendingAttachments;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final attachment in pending)
                        AttachmentChip(
                          attachment: attachment,
                          onRemove: () => controller.removeAttachment(
                            attachment.id,
                          ),
                        ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.bgInput,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        IconButton(
                          onPressed:
                              controller.streaming ? null : controller.pickAttachments,
                          icon: const Icon(Icons.attach_file_rounded),
                          iconSize: 20,
                          color: colors.textTertiary,
                          tooltip: '添加附件',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: TextField(
                              controller: textController,
                              focusNode: focusNode,
                              minLines: 1,
                              maxLines: 6,
                              keyboardType: TextInputType.multiline,
                              textInputAction: appSettings.sendWithEnter
                                  ? TextInputAction.send
                                  : TextInputAction.newline,
                              onSubmitted: appSettings.sendWithEnter
                                  ? (value) => _send()
                                  : null,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: colors.textPrimary,
                              ),
                              cursorColor: colors.brand,
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: '给 DeepSeek 发送消息…',
                                hintStyle: TextStyle(
                                  fontSize: 15,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, right: 2),
                          child: _streamOrSendButton(),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
                      child: Row(
                        children: <Widget>[
                          _TextToggle(
                            icon: Icons.lightbulb_outline_rounded,
                            label: '深度思考',
                            active: controller.deepThinking,
                            onTap: () => controller.setDeepThinking(
                              !controller.deepThinking,
                            ),
                          ),
                          const SizedBox(width: 14),
                          _TextToggle(
                            icon: Icons.language_rounded,
                            label: '联网搜索',
                            active: controller.searchOn,
                            onTap: () => _toggleSearch(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppInfo.disclaimer,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _streamOrSendButton() {
    if (controller.streaming) {
      return _RoundButton(
        icon: Icons.stop_rounded,
        tooltip: '停止生成',
        background: null,
        foreground: null,
        onPressed: _stop,
      );
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: textController,
      builder: (context, value, child) {
        final hasInput =
            value.text.trim().isNotEmpty ||
            controller.pendingAttachments.isNotEmpty;
        return _RoundButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: '发送',
          enabled: controller.canSend && hasInput,
          onPressed: _send,
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    this.enabled = true,
    this.background,
    this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final Color? background;
  final Color? foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bool active = enabled;
    final Color bg = background ??
        (active ? colors.brand : colors.bgHover);
    final Color fg = foreground ??
        (active ? Colors.white : colors.textTertiary);
    return IconButton(
      onPressed: active ? onPressed : null,
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg,
        disabledForegroundColor: fg,
        fixedSize: const Size(30, 30),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _TextToggle extends StatelessWidget {
  const _TextToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = active ? colors.brand : colors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
