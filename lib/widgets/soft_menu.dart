/// 轻量柔和菜单：替代系统 PopupMenu，带淡入 + 缩放缓动，卡片更圆润柔和。
library;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 菜单项描述。
class SoftMenuItem<T> {
  const SoftMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final T value;
  final IconData icon;
  final String label;

  /// 危险操作（删除等），图标与文字用 danger 色。
  final bool destructive;
}

/// 在 [anchor]（全局坐标，一般取按钮的右下角）附近弹出柔和菜单。
///
/// 返回所选菜单项的值；点击遮罩/按返回键返回 null。
Future<T?> showSoftMenu<T>({
  required BuildContext context,
  required Offset anchor,
  required List<SoftMenuItem<T>> items,
  double width = 196,
}) {
  final screen = MediaQuery.sizeOf(context);
  const margin = 12.0;
  const itemHeight = 44.0;
  const cardPadding = 6.0;
  final height = items.length * itemHeight + cardPadding * 2;

  // anchor 偏屏幕下半部分时向上展开，否则向下。
  final openAbove = anchor.dy > screen.height / 2;
  // 菜单相对 anchor 的水平展开方向，用于决定缩放原点。
  final openRight = anchor.dx < screen.width / 2;

  var left = anchor.dx;
  if (left + width > screen.width - margin) {
    left = screen.width - margin - width;
  }
  if (left < margin) left = margin;

  var top = openAbove ? anchor.dy - height : anchor.dy;
  if (top + height > screen.height - margin) {
    top = screen.height - margin - height;
  }
  if (top < margin) top = margin;

  final alignment = Alignment(openRight ? -1 : 1, openAbove ? 1 : -1);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Material(
        type: MaterialType.transparency,
        child: SizedBox.expand(
          child: Stack(
            children: <Widget>[
              Positioned(
                left: left,
                top: top,
                width: width,
                child: _SoftMenuCard<T>(items: items),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: alignment,
          child: child,
        ),
      );
    },
  );
}

class _SoftMenuCard<T> extends StatelessWidget {
  const _SoftMenuCard({super.key, required this.items});

  final List<SoftMenuItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final item in items) _SoftMenuEntry<T>(item: item),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftMenuEntry<T> extends StatelessWidget {
  const _SoftMenuEntry({super.key, required this.item});

  final SoftMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = item.destructive ? colors.danger : colors.textPrimary;
    final iconColor = item.destructive ? colors.danger : colors.textSecondary;

    return InkWell(
      onTap: () => Navigator.of(context).pop(item.value),
      borderRadius: BorderRadius.circular(10),
      hoverColor: colors.bgHover,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: <Widget>[
              Icon(item.icon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
