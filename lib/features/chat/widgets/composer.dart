/// 输入区：圆角 24 卡片、多行输入、附件 / 深度思考 / 联网搜索开关、发送。
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
    return appSettings.searchBackend != SearchBackend.off &&
        settings.searchApiKey.trim().isNotEmpty;
  }

  void _send() {
    if (controller.streaming) return;
    final text = textController.text;
    if (text.trim().isEmpty && controller.pendingAttachments.isEmpty) return;
    focusNode.requestFocus();
    textController.clear();
    controller.sendMessage(text);
  }

  void _toggleSearch(BuildContext context) {
    if (!_searchConfigured) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('尚未配置联网搜索，请先在设置里填写搜索服务 Key'),
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
    final streaming = controller.streaming;
    final pending = controller.pendingAttachments;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
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
                decoration: BoxDecoration(
                  color: colors.bgInput,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: colors.borderStrong),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 14, 0),
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
                          hintText: streaming
                              ? '正在生成回复…'
                              : '给 DeepSeek 发送消息…',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            onPressed:
                                streaming ? null : controller.pickAttachments,
                            icon: const Icon(Icons.attach_file_rounded),
                            iconSize: 20,
                            color: colors.textSecondary,
                            tooltip: '添加附件',
                            visualDensity: VisualDensity.compact,
                          ),
                          _ComposerToggle(
                            icon: Icons.lightbulb_outline_rounded,
                            label: '深度思考',
                            active: controller.deepThinking,
                            onTap: () => controller.setDeepThinking(
                              !controller.deepThinking,
                            ),
                          ),
                          const SizedBox(width: 2),
                          _ComposerToggle(
                            icon: Icons.language_rounded,
                            label: '联网',
                            active: controller.searchOn,
                            onTap: () => _toggleSearch(context),
                          ),
                          const Spacer(),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: textController,
                            builder: (context, value, child) {
                              final hasInput =
                                  value.text.trim().isNotEmpty ||
                                      controller.pendingAttachments.isNotEmpty;
                              final enabled =
                                  controller.canSend && hasInput;
                              return _SendButton(
                                enabled: enabled,
                                onPressed: _send,
                              );
                            },
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
                style: TextStyle(fontSize: 10.5, color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerToggle extends StatelessWidget {
  const _ComposerToggle({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active
                ? colors.brand.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: active ? colors.brandText : colors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? colors.brandText : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
      tooltip: '发送',
      style: IconButton.styleFrom(
        backgroundColor: colors.brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: colors.bgHover,
        disabledForegroundColor: colors.textTertiary,
        fixedSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
    );
  }
}
