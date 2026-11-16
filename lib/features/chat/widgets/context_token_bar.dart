/// 上下文压缩提示：默认隐藏，仅压缩时显示一行 11px 提示。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ContextTokenBar extends StatelessWidget {
  const ContextTokenBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '正在压缩上下文…',
          style: TextStyle(fontSize: 11, color: colors.textTertiary),
        ),
      ),
    );
  }
}
