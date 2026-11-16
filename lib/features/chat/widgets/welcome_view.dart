/// 欢迎页：无消息时展示的极简欢迎头部与 2×2 建议问题。
library;

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key, required this.onPickSuggestion});

  /// 点击建议问题时回调（由外部把文字填入输入框，不直接发送）。
  final ValueChanged<String> onPickSuggestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight > 80
            ? constraints.maxHeight - 32
            : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: colors.brandSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.nightlight_round,
                          size: 20,
                          color: colors.brandText,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppInfo.welcomeTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '我会记住我们聊过的事',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _SuggestionGrid(onPick: onPickSuggestion),
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

class _SuggestionGrid extends StatelessWidget {
  const _SuggestionGrid({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final suggestions = AppInfo.welcomeSuggestions;
    final rows = <Widget>[];
    for (var i = 0; i < suggestions.length; i += 2) {
      final first = suggestions[i];
      final second = i + 1 < suggestions.length ? suggestions[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _SuggestionBlock(text: first, onTap: onPick)),
              if (second != null) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(child: _SuggestionBlock(text: second, onTap: onPick)),
              ] else
                const Spacer(),
            ],
          ),
        ),
      );
      if (i + 2 < suggestions.length) rows.add(const SizedBox(height: 8));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _SuggestionBlock extends StatelessWidget {
  const _SuggestionBlock({required this.text, required this.onTap});

  final String text;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => onTap(text),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.bgInput,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
