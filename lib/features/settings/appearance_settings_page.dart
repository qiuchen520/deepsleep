/// 外观设置：主题与字号。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/profile_models.dart';
import '../../state/app_services.dart';
import 'settings_shared.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key, required this.services});

  final AppServices services;

  String _themeLabel(ThemePreference preference) {
    switch (preference) {
      case ThemePreference.system:
        return '跟随系统';
      case ThemePreference.light:
        return '浅色';
      case ThemePreference.dark:
        return '深色';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final settings = services.settings.settings;
        return SettingsScaffold(
          title: '外观',
          children: <Widget>[
            SettingsSection(
              title: '主题',
              rows: <Widget>[
                SettingsDropdownRow<ThemePreference>(
                  label: '外观模式',
                  value: settings.theme,
                  items: <DropdownMenuItem<ThemePreference>>[
                    for (final preference in ThemePreference.values)
                      DropdownMenuItem<ThemePreference>(
                        value: preference,
                        child: Text(_themeLabel(preference)),
                      ),
                  ],
                  onChanged: (value) => services.settings
                      .update(settings.copyWith(theme: value)),
                ),
              ],
            ),
            SettingsSection(
              title: '字号',
              footnote: '字号缩放会先保存设置，界面缩放将在后续版本生效。',
              rows: <Widget>[
                SettingsDropdownRow<double>(
                  label: '字体大小',
                  value: _nearestFontScale(settings.fontScale),
                  items: const <DropdownMenuItem<double>>[
                    DropdownMenuItem<double>(
                      value: 0.9,
                      child: Text('小 0.9x'),
                    ),
                    DropdownMenuItem<double>(
                      value: 1.0,
                      child: Text('标准 1.0x'),
                    ),
                    DropdownMenuItem<double>(
                      value: 1.1,
                      child: Text('大 1.1x'),
                    ),
                    DropdownMenuItem<double>(
                      value: 1.2,
                      child: Text('特大 1.2x'),
                    ),
                  ],
                  onChanged: (value) => services.settings
                      .update(settings.copyWith(fontScale: value)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '提示：主题切换会立即生效。',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        );
      },
    );
  }

  double _nearestFontScale(double value) {
    const choices = <double>[0.9, 1.0, 1.1, 1.2];
    var best = choices.first;
    var bestDelta = (best - value).abs();
    for (final choice in choices.skip(1)) {
      final delta = (choice - value).abs();
      if (delta < bestDelta) {
        best = choice;
        bestDelta = delta;
      }
    }
    return best;
  }
}
