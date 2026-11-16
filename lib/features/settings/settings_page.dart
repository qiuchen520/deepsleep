/// 设置首页：用户 / 外观 / API / 其他四个分组入口，点击进入对应子页。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../state/app_services.dart';
import 'api_settings_page.dart';
import 'appearance_settings_page.dart';
import 'other_settings_page.dart';
import 'user_settings_page.dart';

/// 设置页入口（app.dart 直接使用）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.services});

  final AppServices services;

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              _SettingsEntryCard(
                icon: Icons.person_outline_rounded,
                title: '用户',
                subtitle: '用户档案、人设与切换',
                onTap: () => _push(context, UserSettingsPage(services: services)),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsEntryCard(
                icon: Icons.palette_outlined,
                title: '外观',
                subtitle: '主题与字号',
                onTap: () =>
                    _push(context, AppearanceSettingsPage(services: services)),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsEntryCard(
                icon: Icons.key_outlined,
                title: 'API',
                subtitle: 'Base URL、模型与 API Key',
                onTap: () => _push(context, ApiSettingsPage(services: services)),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsEntryCard(
                icon: Icons.tune_rounded,
                title: '其他',
                subtitle: '语音、记忆、上下文、数据与关于',
                onTap: () =>
                    _push(context, OtherSettingsPage(services: services)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsEntryCard extends StatelessWidget {
  const _SettingsEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.bgElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.brandSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: colors.brandText),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
