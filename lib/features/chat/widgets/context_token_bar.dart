/// 上下文占用提示条：显示估算 token、压缩状态与「已压缩」标记。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ContextTokenBar extends StatelessWidget {
  const ContextTokenBar({
    super.key,
    required this.tokens,
    this.compressing = false,
    this.hasSummary = false,
  });

  final int tokens;
  final bool compressing;
  final bool hasSummary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = <Widget>[
      Icon(Icons.speed_rounded, size: 13, color: colors.textTertiary),
      const SizedBox(width: 4),
      Text(
        '上下文 ≈ $tokens tokens',
        style: TextStyle(fontSize: 11, color: colors.textTertiary),
      ),
    ];
    if (compressing) {
      children.addAll(<Widget>[
        const SizedBox(width: 10),
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: colors.brand,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '正在压缩上下文…',
          style: TextStyle(fontSize: 11, color: colors.brandText),
        ),
      ]);
    }
    if (hasSummary) {
      children.addAll(<Widget>[
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: colors.brandSoft,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.compress_rounded, size: 10, color: colors.brandText),
              const SizedBox(width: 3),
              Text(
                '已压缩',
                style: TextStyle(fontSize: 10, color: colors.brandText),
              ),
            ],
          ),
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 0,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
  }
}
