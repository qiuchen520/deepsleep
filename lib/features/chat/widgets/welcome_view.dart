/// 欢迎页：无消息时展示的大标题与建议问题（点击填入输入框，不直接发送）。
library;

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.onPickSuggestion,
    this.hasApiKey = true,
    this.onOpenSettings,
  });

  /// 点击建议问题时回调（由外部把文字填入输入框）。
  final ValueChanged<String> onPickSuggestion;

  /// 是否已配置 API Key；未配置时展示前往设置的提示。
  final bool hasApiKey;

  /// 未配置 API Key 时点击提示去设置。
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final openSettings = onOpenSettings;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 120
                  ? constraints.maxHeight - AppSpacing.xxl
                  : 0.0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colors.brandSoft,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 26,
                        color: colors.brandText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      AppInfo.welcomeTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'DeepSleep 会记住你的偏好与上下文，越聊越懂你',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        for (final suggestion in AppInfo.welcomeSuggestions)
                          _SuggestionCard(
                            text: suggestion,
                            onTap: () => onPickSuggestion(suggestion),
                          ),
                      ],
                    ),
                    if (!hasApiKey && openSettings != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xl),
                      InkWell(
                        onTap: openSettings,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.key_off_outlined,
                                size: 15,
                                color: colors.warning,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '尚未配置 API Key，点此前往设置',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 280,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.bgElevated,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 15,
                  color: colors.brandText,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
