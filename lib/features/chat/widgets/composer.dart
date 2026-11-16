/// 输入区：底部 sticky 输入卡片 + 功能行 + 免责声明。
///
/// 对齐 docs/UI_SPEC.md：外层宽 776、max-width calc(100%-32)；卡片圆角 24、
/// 1px 边框、欢迎页阴影（深色无阴影）；输入 16/24、最小高 60、内边距
/// 12 12 0 16；发送按钮 34×34；功能行 padding 12、gap 8；开关高 34、圆角 18、
/// 字号 13/20；免责声明 11/16 居中。
library;

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/profile_models.dart';
import '../../../state/app_services.dart';
import '../../../state/conversation_controller.dart';
import '../../../state/settings_controller.dart';
import 'attachment_preview.dart';
import 'model_picker_sheet.dart';

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.settings,
    required this.textController,
    required this.focusNode,
    required this.onOpenSettings,
    required this.services,
  });

  final ConversationController controller;
  final SettingsController settings;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onOpenSettings;
  final AppServices services;

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

  List<BoxShadow> _cardShadow(BuildContext context) {
    if (context.isDark) return const <BoxShadow>[];
    final colors = context.colors;
    if (controller.messages.isEmpty) {
      // 欢迎页阴影（Spec §5）。
      return <BoxShadow>[
        BoxShadow(
          color: colors.shadow.withValues(alpha: 0.02),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: colors.brand.withValues(alpha: 0.01),
          blurRadius: 2,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: colors.brand.withValues(alpha: 0.03),
          blurRadius: 60,
          offset: const Offset(0, 30),
        ),
      ];
    }
    // 会话中阴影。
    return <BoxShadow>[
      BoxShadow(
        color: colors.shadow.withValues(alpha: 0.02),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: colors.shadow.withValues(alpha: 0.04),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = context.colors;
    final appSettings = settings.settings;
    final pending = controller.pendingAttachments;
    final borderColor = context.isDark ? colors.border : colors.borderStrong;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 776),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: colors.bgInput,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: focusNode.hasFocus
                        ? colors.brand.withValues(alpha: 0.45)
                        : borderColor,
                  ),
                  boxShadow: _cardShadow(context),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (pending.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 60),
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
                            fontSize: 16,
                            height: 24 / 16,
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
                              fontSize: 16,
                              height: 24 / 16,
                              // 近似 Spec 的 caption 色（浅 #ADB2B8 / 深 #81858C）。
                              color: colors.textTertiary.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                IconButton(
                                  onPressed: controller.streaming
                                      ? null
                                      : controller.pickAttachments,
                                  icon: const Icon(Icons.attach_file_rounded),
                                  iconSize: 20,
                                  color: colors.textTertiary,
                                  tooltip: '添加附件',
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 34,
                                    height: 34,
                                  ),
                                ),
                                _ModelChip(
                                  label: shortModelName(
                                    appSettings.effectiveModel,
                                    appSettings,
                                  ),
                                  onTap: () =>
                                      showModelPicker(context, services),
                                ),
                                _Toggle(
                                  icon: Icons.lightbulb_outline_rounded,
                                  label: '深度思考',
                                  active: controller.deepThinking,
                                  onTap: () => controller.setDeepThinking(
                                    !controller.deepThinking,
                                  ),
                                ),
                                _Toggle(
                                  icon: Icons.language_rounded,
                                  label: '智能搜索',
                                  active: controller.searchOn,
                                  onTap: () => _toggleSearch(context),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _streamOrSendButton(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  AppInfo.disclaimer,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 16 / 11,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _streamOrSendButton() {
    if (controller.streaming) {
      return _SendButton(
        icon: Icons.stop_rounded,
        tooltip: '停止生成',
        onPressed: _stop,
      );
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: textController,
      builder: (context, value, child) {
        final hasInput =
            value.text.trim().isNotEmpty ||
            controller.pendingAttachments.isNotEmpty;
        final enabled = controller.canSend && hasInput;
        return _SendButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: '发送',
          enabled: enabled,
          onPressed: _send,
        );
      },
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.icon,
    required this.tooltip,
    this.enabled = true,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: colors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.brand.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white,
          fixedSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 20 / 13,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? colors.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? colors.brand.withValues(alpha: 0.32)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 20 / 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
