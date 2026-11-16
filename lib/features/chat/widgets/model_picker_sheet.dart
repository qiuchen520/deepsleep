/// 模型选择面板：展示自动检测到的模型，支持手动刷新检测。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/profile_models.dart';
import '../../../state/app_services.dart';

/// 打开模型选择底部面板。
Future<void> showModelPicker(BuildContext context, AppServices services) async {
  final settings = services.settings;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.bgElevated,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final colors = context.colors;
          final current = settings.settings.chatModel;
          final models = <String>[
            ...settings.candidateModels,
            if (!settings.candidateModels.contains(current)) current,
          ];
          Future<void> detect() async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            try {
              final detected = await services.api.listModels();
              await settings.setAvailableModels(detected);
              if (!context.mounted) return;
              setState(() {});
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    detected.isEmpty
                        ? '没有检测到模型，保留默认列表'
                        : '检测到 ${detected.length} 个模型',
                  ),
                ),
              );
            } catch (e) {
              messenger?.showSnackBar(
                SnackBar(content: Text('检测失败：$e')),
              );
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        '选择模型',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: detect,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('自动检测'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final model in models)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        model,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        _describe(model),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textTertiary,
                        ),
                      ),
                      trailing: model == current
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: colors.brand,
                            )
                          : null,
                      onTap: () async {
                        await settings.update(
                          settings.settings.copyWith(
                            chatModel: model,
                            deepThinking: false,
                          ),
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '深度思考',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      '使用 ${settings.settings.reasonerModel} 思考后再回答',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                    value: settings.settings.deepThinking,
                    activeTrackColor: colors.brand,
                    onChanged: (value) async {
                      await settings.update(
                        settings.settings.copyWith(deepThinking: value),
                      );
                      if (context.mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _describe(String model) {
  final lower = model.toLowerCase();
  if (lower.contains('reasoner')) return '深度思考 · 推理模型';
  if (lower.contains('deepseek') || lower.contains('chat')) {
    return '通用对话';
  }
  return '自定义模型';
}

/// 把模型 id 缩写显示在输入区按钮上。
String shortModelName(String model, AppSettings settings) {
  if (model == settings.reasonerModel) return 'Reasoner';
  if (model == settings.chatModel) {
    final lower = model.toLowerCase();
    if (lower.contains('chat')) return 'DeepSeek';
    return model;
  }
  return model;
}
