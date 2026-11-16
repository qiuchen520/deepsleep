/// 欢迎页：空会话时仅展示居中的问候语（Spec：无 logo、无建议问题块）。
///
/// 对齐 docs/UI_SPEC.md：标题 24/32、600、居中；内容列 max-width 840、
/// padding 0 32 64；垂直居中；标题下 21px；≤439px 时 20/28、500。
library;

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final horizontal = screenWidth < 768 ? 16.0 : 32.0;
        final compactTitle = screenWidth < 440;
        final minHeight = constraints.maxHeight > 0
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 64),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 840 - horizontal * 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        AppInfo.welcomeTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compactTitle ? 20 : 24,
                          height: compactTitle ? 28 / 20 : 32 / 24,
                          fontWeight:
                              compactTitle ? FontWeight.w500 : FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 21),
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
}
