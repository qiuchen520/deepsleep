/// 错误提示：13px danger 文字 + 文字按钮「重试」，不使用卡片。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final retry = onRetry;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: colors.danger,
            ),
          ),
          if (retry != null)
            TextButton(
              onPressed: retry,
              style: TextButton.styleFrom(
                foregroundColor: colors.danger,
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重试', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
