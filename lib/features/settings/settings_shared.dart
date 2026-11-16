/// 设置模块共享 UI：统一的分组卡片、设置行与用户档案编辑弹窗。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/profile_models.dart';
import '../../widgets/soft_modal.dart';

/// 设置子页统一骨架：AppBar + 居中限宽 640 的可滚动列表。
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
            children: children,
          ),
        ),
      ),
    );
  }
}

/// 分组卡片：标题 + 圆角卡片内的若干行（行间 1px 分隔）+ 可选说明。
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.rows,
    this.footnote,
  });

  final String title;
  final List<Widget> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(height: 1, thickness: 1, color: colors.border));
      }
      children.add(rows[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
              ),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.bgElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(children: children),
          ),
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: Text(
                footnote!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 普通设置行。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.valueText,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final String label;
  final String? valueText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: danger ? colors.danger : colors.textPrimary,
                  ),
                ),
              ),
              if (valueText != null)
                Text(
                  valueText!,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.textTertiary,
                  ),
                ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// 开关行（整行可点）。
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// 下拉选择行。
class SettingsDropdownRow<T> extends StatelessWidget {
  const SettingsDropdownRow({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
              ),
            ),
            DropdownButton<T>(
              value: value,
              isDense: true,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              icon: Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: colors.textTertiary,
              ),
              style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              items: items,
              onChanged: (next) {
                if (next == null) return;
                onChanged(next);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 行内输入框（右对齐、无边框）。
class SettingsInputRow extends StatelessWidget {
  const SettingsInputRow({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscured = false,
    this.onToggleObscure,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscured;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscured,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: keyboardType,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: colors.textTertiary,
                  ),
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: onToggleObscure == null
                      ? null
                      : IconButton(
                          tooltip: obscured ? '显示' : '隐藏',
                          onPressed: onToggleObscure,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                          icon: Icon(
                            obscured
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: colors.textTertiary,
                          ),
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 动作行（保存 / 验证 / 危险操作等）。
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.label,
    this.onTap,
    this.danger = false,
    this.loading = false,
    this.trailingText,
  });

  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool loading;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: loading ? null : onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: danger ? colors.danger : colors.brandText,
                ),
              ),
              if (loading) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ],
              const Spacer(),
              if (trailingText != null)
                Text(
                  trailingText!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 滑杆行（标题 + 数值 + 滑杆）。
class SettingsSliderRow extends StatelessWidget {
  const SettingsSliderRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
              Text(
                valueText,
                style: TextStyle(fontSize: 13, color: colors.textTertiary),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueText,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 用户档案编辑（统一 soft_modal）
// -----------------------------------------------------------------------------

/// 用户档案编辑草稿。
class ProfileDraft {
  const ProfileDraft({
    required this.name,
    required this.emoji,
    required this.persona,
  });

  final String name;
  final String emoji;
  final String persona;
}

/// 弹出统一风格的用户档案编辑弹窗。
Future<ProfileDraft?> showProfileEditor(
  BuildContext context, {
  UserProfile? profile,
}) {
  return showSoftDialog<ProfileDraft>(
    context: context,
    title: profile == null ? '新增用户档案' : '编辑用户档案',
    child: _ProfileEditorForm(profile: profile),
  );
}

class _ProfileEditorForm extends StatefulWidget {
  const _ProfileEditorForm({super.key, this.profile});

  final UserProfile? profile;

  @override
  State<_ProfileEditorForm> createState() => _ProfileEditorFormState();
}

class _ProfileEditorFormState extends State<_ProfileEditorForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _emojiController;
  late final TextEditingController _personaController;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _emojiController = TextEditingController(text: profile?.emoji ?? '🧑');
    _personaController = TextEditingController(text: profile?.persona ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    _personaController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      ProfileDraft(
        name: name,
        emoji: _emojiController.text.trim().isEmpty
            ? '🧑'
            : _emojiController.text.trim(),
        persona: _personaController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 64,
              child: TextField(
                controller: _emojiController,
                maxLength: 2,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: '头像',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: _nameController,
                maxLength: 20,
                autofocus: true,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: '名字',
                  counterText: '',
                  hintText: '例如：工作号',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _personaController,
          maxLines: 3,
          maxLength: 300,
          style: TextStyle(fontSize: 15, color: colors.textPrimary),
          decoration: const InputDecoration(
            labelText: '人设（可选）',
            hintText: '例如：回答尽量简短，称呼我为「老板」。',
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
              ),
              child: const Text('取消'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nameController,
              builder: (context, value, _) {
                return FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _save,
                  child: const Text('保存'),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
