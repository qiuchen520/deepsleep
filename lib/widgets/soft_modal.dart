/// 统一的高级感弹窗 / 面板样式。
///
/// 目标：所有弹窗共用同一套「大肚子」外观（固定最大宽度、统一圆角/内边距/
/// 毛玻璃背景/遮罩/动效），避免不同功能弹窗尺寸参差。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 弹窗统一尺寸令牌。
class SoftModalTokens {
  SoftModalTokens._();

  static const double maxWidth = 560;
  static const double radius = 28;
  static const double padding = 24;
  static const double headerGap = 14;
  static const Duration duration = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}

/// 统一毛玻璃卡片：白色半透明 + 背景模糊 + 圆角 + 柔和阴影。
class SoftGlassCard extends StatelessWidget {
  const SoftGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SoftModalTokens.padding),
    this.maxWidth = SoftModalTokens.maxWidth,
  });

  final Widget child;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        minWidth: 280,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SoftModalTokens.radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: colors.bgElevated.withValues(alpha: isDark ? 0.88 : 0.92),
              borderRadius: BorderRadius.circular(SoftModalTokens.radius),
              border: Border.all(
                color: colors.border.withValues(alpha: isDark ? 0.9 : 0.7),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 打开统一风格弹窗。
Future<T?> showSoftDialog<T>({
  required BuildContext context,
  String? title,
  String? description,
  Widget? child,
  List<Widget> actions = const <Widget>[],
  bool dismissible = true,
  double maxWidth = SoftModalTokens.maxWidth,
  EdgeInsets? padding,
}) {
  final colors = context.colors;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: title ?? '',
    barrierColor: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.26),
    transitionDuration: SoftModalTokens.duration,
    pageBuilder: (dialogContext, _, __) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Material(
            color: Colors.transparent,
            child: SoftGlassCard(
              maxWidth: maxWidth,
              padding: padding ?? const EdgeInsets.all(SoftModalTokens.padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (title != null && title.isNotEmpty) ...<Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 19,
                              height: 26 / 19,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (dismissible)
                          _CloseButton(
                            onTap: () => Navigator.of(dialogContext).pop(),
                          ),
                      ],
                    ),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 21 / 13.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: SoftModalTokens.headerGap),
                  ],
                  if (child != null) child,
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          for (var i = 0; i < actions.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 10),
                            actions[i],
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: SoftModalTokens.curve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 统一确认弹窗（危险操作可设 destructive）。
Future<bool> showSoftConfirm({
  required BuildContext context,
  required String title,
  String? description,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final colors = context.colors;
  final result = await showSoftDialog<bool>(
    context: context,
    title: title,
    description: description,
    maxWidth: 460,
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        style: TextButton.styleFrom(
          foregroundColor: colors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        child: Text(cancelLabel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        style: FilledButton.styleFrom(
          backgroundColor: destructive ? colors.danger : colors.brand,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(confirmLabel),
      ),
    ],
  );
  return result ?? false;
}

/// 统一输入弹窗。
Future<String?> showSoftInputDialog({
  required BuildContext context,
  required String title,
  String? description,
  String? initialValue,
  String hintText = '',
  String confirmLabel = '保存',
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  final colors = context.colors;
  final result = await showSoftDialog<String>(
    context: context,
    title: title,
    description: description,
    child: TextField(
      controller: controller,
      autofocus: true,
      maxLines: maxLines,
      style: TextStyle(fontSize: 15, height: 1.5, color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: colors.bgInput,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(controller.text),
        style: FilledButton.styleFrom(
          backgroundColor: colors.brand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(confirmLabel),
      ),
    ],
  );
  controller.dispose();
  return result;
}

/// 统一底部面板（毛玻璃 + 大圆角）。
Future<T?> showSoftSheet<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  bool isScrollControlled = true,
}) {
  final colors = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.26),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: colors.bgElevated.withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(color: colors.border),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: colors.borderStrong,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    Flexible(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.bgHover,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.close_rounded, size: 18, color: colors.textSecondary),
      ),
    );
  }
}
