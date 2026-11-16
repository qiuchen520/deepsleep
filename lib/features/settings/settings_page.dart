/// 设置页：iOS 分组列表样式（API / 对话 / 搜索 / 记忆 / 上下文 / 外观 /
/// 用户档案 / 数据 / 关于），保留全部配置与交互。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/profile_models.dart';
import '../../services/contracts.dart';
import '../../state/app_services.dart';

/// 设置页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 搜索服务商的界面选项。
enum _SearchChoice { off, builtin, tavily, serper }

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _chatModelController;
  late final TextEditingController _reasonerModelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _searchKeyController;
  late final TextEditingController _mem0UrlController;
  late final TextEditingController _mem0KeyController;

  bool _obscureApiKey = true;
  bool _obscureSearchKey = true;
  bool _obscureMem0Key = true;
  bool _validating = false;
  bool _exporting = false;
  bool _importing = false;

  double _compressThreshold = AppInfo.defaultCompressThreshold.toDouble();
  double _memoryBudget = AppInfo.memoryTokenBudget.toDouble();

  @override
  void initState() {
    super.initState();
    final controller = widget.services.settings;
    final settings = controller.settings;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _chatModelController = TextEditingController(text: settings.chatModel);
    _reasonerModelController =
        TextEditingController(text: settings.reasonerModel);
    _apiKeyController = TextEditingController(text: controller.apiKey);
    _searchKeyController = TextEditingController(text: controller.searchApiKey);
    _mem0UrlController = TextEditingController(text: settings.mem0ApiUrl);
    _mem0KeyController = TextEditingController(text: controller.mem0ApiKey);
    _compressThreshold = settings.compressThreshold
        .clamp(2000, 12000)
        .toDouble();
    _memoryBudget = settings.memoryTokenBudget
        .clamp(200, 1200)
        .toDouble();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _chatModelController.dispose();
    _reasonerModelController.dispose();
    _apiKeyController.dispose();
    _searchKeyController.dispose();
    _mem0UrlController.dispose();
    _mem0KeyController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 通用工具
  // ---------------------------------------------------------------------------

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _update(AppSettings next) async {
    await widget.services.settings.update(next);
  }

  Future<void> _openUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(SnackBar(content: Text('链接无效：$url')));
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('打开链接失败：$error')));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmLabel = '确定',
  }) async {
    final colors = context.colors;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // 分组与行
  // ---------------------------------------------------------------------------

  Widget _section(
    BuildContext context, {
    required String title,
    required List<Widget> rows,
    String? footnote,
  }) {
    final colors = context.colors;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Divider(height: 1, thickness: 1, color: colors.border),
        );
      }
      children.add(rows[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              '· $title',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
              ),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.bgElevated,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.border),
            ),
            child: Column(children: children),
          ),
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 6),
              child: Text(
                footnote,
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

  Widget _row(
    BuildContext context, {
    required String label,
    String? valueText,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
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
                  valueText,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.textTertiary,
                  ),
                ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputRow(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscured = false,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
  }) {
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

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
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

  Widget _dropdownRow<T>(
    BuildContext context, {
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onChanged,
  }) {
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
                Icons.expand_more,
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

  Widget _actionRow(
    BuildContext context, {
    required String label,
    VoidCallback? onTap,
    bool danger = false,
    bool loading = false,
  }) {
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderBlock(
    BuildContext context, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
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

  // ---------------------------------------------------------------------------
  // API 配置
  // ---------------------------------------------------------------------------

  Future<void> _saveApiConfig() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = widget.services.settings;
    final current = controller.settings;
    final baseUrl = _baseUrlController.text.trim();
    final chatModel = _chatModelController.text.trim();
    final reasonerModel = _reasonerModelController.text.trim();
    await controller.update(
      current.copyWith(
        baseUrl: baseUrl.isEmpty ? AppInfo.defaultBaseUrl : baseUrl,
        chatModel: chatModel.isEmpty ? AppInfo.defaultChatModel : chatModel,
        reasonerModel: reasonerModel.isEmpty
            ? AppInfo.defaultReasonerModel
            : reasonerModel,
      ),
    );
    await controller.setApiKey(_apiKeyController.text);
    messenger.showSnackBar(
      const SnackBar(content: Text('API 配置已保存')),
    );
  }

  Future<void> _validateApiKey() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_apiKeyController.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请先填写 API Key')),
      );
      return;
    }
    setState(() => _validating = true);
    try {
      await widget.services.settings.setApiKey(_apiKeyController.text);
      await widget.services.api.validateApiKey();
      messenger.showSnackBar(
        const SnackBar(content: Text('API Key 验证通过')),
      );
    } catch (error) {
      final message =
          error is ApiException ? error.friendlyMessage : '验证失败：$error';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Widget _buildApiSection(BuildContext context) {
    return _section(
      context,
      title: 'API',
      footnote: 'Key 保存在系统安全存储中，不会写入备份文件。',
      rows: <Widget>[
        _inputRow(
          context,
          label: 'Base URL',
          controller: _baseUrlController,
          hint: AppInfo.defaultBaseUrl,
          keyboardType: TextInputType.url,
        ),
        _inputRow(
          context,
          label: '对话模型',
          controller: _chatModelController,
          hint: AppInfo.defaultChatModel,
        ),
        _inputRow(
          context,
          label: '推理模型',
          controller: _reasonerModelController,
          hint: AppInfo.defaultReasonerModel,
        ),
        _inputRow(
          context,
          label: 'API Key',
          controller: _apiKeyController,
          hint: 'sk-...',
          obscured: _obscureApiKey,
          onToggleObscure: () =>
              setState(() => _obscureApiKey = !_obscureApiKey),
        ),
        _actionRow(context, label: '保存 API 配置', onTap: _saveApiConfig),
        _actionRow(
          context,
          label: '验证 API Key',
          onTap: _validateApiKey,
          loading: _validating,
        ),
        _actionRow(
          context,
          label: '前往充值',
          onTap: () => _openUrl('https://platform.deepseek.com/top_up'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 对话与搜索
  // ---------------------------------------------------------------------------

  Future<void> _saveSearchKey() async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.services.settings.setSearchApiKey(_searchKeyController.text);
    messenger.showSnackBar(
      const SnackBar(content: Text('搜索 API Key 已保存')),
    );
  }

  Future<void> _changeSearchBackend(SearchBackend backend) async {
    final controller = widget.services.settings;
    await controller.update(
      controller.settings.copyWith(searchBackend: backend),
    );
    final needsKey = backend == SearchBackend.tavily ||
        backend == SearchBackend.serper;
    if (backend == SearchBackend.deepseek) {
      if (!mounted) return;
      _toast('已启用 DeepSeek 内置搜索，无需额外 API Key');
      return;
    }
    if (needsKey && controller.searchApiKey.trim().isEmpty) {
      if (!mounted) return;
      _toast('已开启搜索，请填写对应的搜索 API Key');
    }
  }

  _SearchChoice _searchChoiceOf(SearchBackend backend) {
    switch (backend) {
      case SearchBackend.off:
        return _SearchChoice.off;
      case SearchBackend.deepseek:
        return _SearchChoice.builtin;
      case SearchBackend.tavily:
        return _SearchChoice.tavily;
      case SearchBackend.serper:
        return _SearchChoice.serper;
    }
  }

  String _searchChoiceLabel(_SearchChoice choice) {
    switch (choice) {
      case _SearchChoice.off:
        return '关闭';
      case _SearchChoice.builtin:
        return 'DeepSeek 内置搜索（推荐）';
      case _SearchChoice.tavily:
        return 'Tavily';
      case _SearchChoice.serper:
        return 'Serper';
    }
  }

  Future<void> _onSearchChoice(_SearchChoice choice) async {
    switch (choice) {
      case _SearchChoice.off:
        await _changeSearchBackend(SearchBackend.off);
        break;
      case _SearchChoice.tavily:
        await _changeSearchBackend(SearchBackend.tavily);
        break;
      case _SearchChoice.serper:
        await _changeSearchBackend(SearchBackend.serper);
        break;
      case _SearchChoice.builtin:
        await _changeSearchBackend(SearchBackend.deepseek);
        break;
    }
  }

  Widget _buildChatSection(BuildContext context, AppSettings settings) {
    return _section(
      context,
      title: '对话',
      rows: <Widget>[
        _switchRow(
          context,
          label: '深度思考',
          value: settings.deepThinking,
          onChanged: (value) =>
              _update(settings.copyWith(deepThinking: value)),
        ),
        _switchRow(
          context,
          label: 'Enter 发送',
          value: settings.sendWithEnter,
          onChanged: (value) =>
              _update(settings.copyWith(sendWithEnter: value)),
        ),
        _switchRow(
          context,
          label: '显示 token 用量',
          value: settings.showTokenUsage,
          onChanged: (value) =>
              _update(settings.copyWith(showTokenUsage: value)),
        ),
      ],
    );
  }

  Widget _buildSearchSection(BuildContext context, AppSettings settings) {
    final showKey = settings.searchBackend == SearchBackend.tavily ||
        settings.searchBackend == SearchBackend.serper;
    final choices = <DropdownMenuItem<_SearchChoice>>[
      for (final choice in _SearchChoice.values)
        DropdownMenuItem<_SearchChoice>(
          value: choice,
          child: Text(_searchChoiceLabel(choice)),
        ),
    ];
    return _section(
      context,
      title: '联网搜索',
      footnote: showKey
          ? 'Tavily 可在 tavily.com 申请 Key，Serper 可在 serper.dev 申请。'
          : null,
      rows: <Widget>[
        _dropdownRow<_SearchChoice>(
          context,
          label: '搜索服务商',
          value: _searchChoiceOf(settings.searchBackend),
          items: choices,
          onChanged: _onSearchChoice,
        ),
        if (showKey) ...<Widget>[
          _inputRow(
            context,
            label: '搜索 API Key',
            controller: _searchKeyController,
            hint: settings.searchBackend == SearchBackend.serper
                ? 'serper.dev API Key'
                : 'tvly-...',
            obscured: _obscureSearchKey,
            onToggleObscure: () =>
                setState(() => _obscureSearchKey = !_obscureSearchKey),
          ),
          _actionRow(context, label: '保存搜索 Key', onTap: _saveSearchKey),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 记忆
  // ---------------------------------------------------------------------------

  Future<void> _changeMemoryBackend(MemoryBackend backend) async {
    final controller = widget.services.settings;
    if (backend == controller.settings.memoryBackend) return;
    if (backend == MemoryBackend.mem0) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('实验性功能'),
            content: const Text(
              'mem0 云平台适配仍处于实验阶段，可能无法正常工作。\n\n'
              '切换后本地记忆网仍然保留，可随时切回。是否继续？',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('仍要切换'),
              ),
            ],
          );
        },
      );
      if (agreed != true) return;
    }
    await controller.update(
      controller.settings.copyWith(memoryBackend: backend),
    );
    if (!mounted) return;
    _toast(
      backend == MemoryBackend.mem0
          ? '已切换到 mem0 云平台（实验性）'
          : '已切换到本地知识网',
    );
  }

  Future<void> _saveMem0Config() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = widget.services.settings;
    final url = _mem0UrlController.text.trim();
    await controller.update(
      controller.settings.copyWith(
        mem0ApiUrl: url.isEmpty ? 'https://api.mem0.ai' : url,
      ),
    );
    await controller.setMem0ApiKey(_mem0KeyController.text);
    messenger.showSnackBar(
      const SnackBar(content: Text('mem0 配置已保存')),
    );
  }

  Widget _buildMemorySection(BuildContext context, AppSettings settings) {
    final isMem0 = settings.memoryBackend == MemoryBackend.mem0;
    return _section(
      context,
      title: '记忆',
      footnote: isMem0 ? 'mem0 为实验性选项，需联网写入云端。' : null,
      rows: <Widget>[
        _switchRow(
          context,
          label: '长期记忆',
          value: settings.memoryEnabled,
          onChanged: (value) =>
              _update(settings.copyWith(memoryEnabled: value)),
        ),
        _switchRow(
          context,
          label: '自动抽取记忆',
          value: settings.autoExtractMemory,
          onChanged: (value) =>
              _update(settings.copyWith(autoExtractMemory: value)),
        ),
        _dropdownRow<MemoryBackend>(
          context,
          label: '记忆后端',
          value: settings.memoryBackend,
          items: const <DropdownMenuItem<MemoryBackend>>[
            DropdownMenuItem<MemoryBackend>(
              value: MemoryBackend.local,
              child: Text('本地知识网'),
            ),
            DropdownMenuItem<MemoryBackend>(
              value: MemoryBackend.mem0,
              child: Text('mem0 云平台'),
            ),
          ],
          onChanged: _changeMemoryBackend,
        ),
        if (isMem0) ...<Widget>[
          _inputRow(
            context,
            label: 'mem0 API URL',
            controller: _mem0UrlController,
            hint: 'https://api.mem0.ai',
            keyboardType: TextInputType.url,
          ),
          _inputRow(
            context,
            label: 'mem0 API Key',
            controller: _mem0KeyController,
            hint: 'm0-...',
            obscured: _obscureMem0Key,
            onToggleObscure: () =>
                setState(() => _obscureMem0Key = !_obscureMem0Key),
          ),
          _actionRow(context, label: '保存 mem0 配置', onTap: _saveMem0Config),
        ],
      ],
    );
  }

  Widget _buildContextSection(BuildContext context, AppSettings settings) {
    return _section(
      context,
      title: '上下文',
      footnote: '阈值越小越省 token，但更快丢失细节；记忆预算越大越「记得多」。',
      rows: <Widget>[
        _sliderBlock(
          context,
          label: '上下文压缩阈值',
          valueText: '${_compressThreshold.round()} tokens',
          value: _compressThreshold,
          min: 2000,
          max: 12000,
          divisions: 20,
          onChanged: (value) => setState(() => _compressThreshold = value),
          onChangeEnd: (value) => _update(
            settings.copyWith(compressThreshold: value.round()),
          ),
        ),
        _sliderBlock(
          context,
          label: '记忆注入预算',
          valueText: '${_memoryBudget.round()} tokens',
          value: _memoryBudget,
          min: 200,
          max: 1200,
          divisions: 20,
          onChanged: (value) => setState(() => _memoryBudget = value),
          onChangeEnd: (value) => _update(
            settings.copyWith(memoryTokenBudget: value.round()),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 外观
  // ---------------------------------------------------------------------------

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

  double _currentFontScale(double value) {
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

  Widget _buildAppearanceSection(BuildContext context, AppSettings settings) {
    return _section(
      context,
      title: '外观',
      footnote: '字号缩放会先保存设置，界面缩放将在后续版本生效。',
      rows: <Widget>[
        _dropdownRow<ThemePreference>(
          context,
          label: '主题',
          value: settings.theme,
          items: <DropdownMenuItem<ThemePreference>>[
            for (final preference in ThemePreference.values)
              DropdownMenuItem<ThemePreference>(
                value: preference,
                child: Text(_themeLabel(preference)),
              ),
          ],
          onChanged: (value) => _update(settings.copyWith(theme: value)),
        ),
        _dropdownRow<double>(
          context,
          label: '字号',
          value: _currentFontScale(settings.fontScale),
          items: const <DropdownMenuItem<double>>[
            DropdownMenuItem<double>(value: 0.9, child: Text('小 0.9x')),
            DropdownMenuItem<double>(value: 1.0, child: Text('标准 1.0x')),
            DropdownMenuItem<double>(value: 1.1, child: Text('大 1.1x')),
            DropdownMenuItem<double>(value: 1.2, child: Text('特大 1.2x')),
          ],
          onChanged: (value) => _update(settings.copyWith(fontScale: value)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 用户档案
  // ---------------------------------------------------------------------------

  Future<void> _switchProfile(UserProfile profile) async {
    if (widget.services.settings.settings.activeProfileId == profile.id) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = widget.services.settings;
    await controller.switchProfile(profile.id);
    await widget.services.conversations.reloadForProfile();
    await widget.services.memories.refresh();
    messenger.showSnackBar(
      SnackBar(content: Text('已切换到「${profile.name}」')),
    );
  }

  Future<void> _editProfile(UserProfile? profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = widget.services.settings;
    final draft = await showDialog<_ProfileDraft>(
      context: context,
      builder: (_) => _ProfileEditorDialog(profile: profile),
    );
    if (draft == null) return;
    if (profile == null) {
      final created = await controller.createProfile(
        name: draft.name,
        emoji: draft.emoji,
        persona: draft.persona,
      );
      await controller.switchProfile(created.id);
      await widget.services.conversations.reloadForProfile();
      await widget.services.memories.refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('已新增并切换到新档案')),
      );
    } else {
      await controller.updateProfile(
        profile.copyWith(
          name: draft.name,
          emoji: draft.emoji,
          persona: draft.persona,
        ),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('用户档案已更新')),
      );
    }
  }

  Future<void> _deleteProfile(UserProfile profile) async {
    final controller = widget.services.settings;
    if (controller.profiles.length <= 1) {
      _toast('至少保留一个用户档案');
      return;
    }
    final confirmed = await _confirm(
      title: '删除用户档案',
      message: '删除后该档案将不再出现在切换列表中（其对话与记忆仍保留在本地）。'
          '\n\n确定删除「${profile.name}」吗？',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    final wasActive = controller.settings.activeProfileId == profile.id;
    await controller.deleteProfile(profile.id);
    if (wasActive) {
      await widget.services.conversations.reloadForProfile();
      await widget.services.memories.refresh();
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('用户档案已删除')),
    );
  }

  Widget _buildProfileRow(BuildContext context, UserProfile profile) {
    final colors = context.colors;
    final isActive =
        widget.services.settings.settings.activeProfileId == profile.id;
    return InkWell(
      onTap: () => _switchProfile(profile),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Text(profile.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (isActive)
                Text(
                  '当前',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textTertiary,
                  ),
                ),
              IconButton(
                tooltip: '编辑档案',
                iconSize: 16,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                onPressed: () => _editProfile(profile),
                icon: Icon(Icons.edit_outlined, color: colors.textTertiary),
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                tooltip: '删除档案',
                iconSize: 16,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                onPressed: () => _deleteProfile(profile),
                icon: Icon(Icons.delete_outline, color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfilesSection(BuildContext context) {
    final controller = widget.services.settings;
    final rows = <Widget>[
      for (final profile in controller.profiles)
        _buildProfileRow(context, profile),
      _actionRow(
        context,
        label: '新增档案',
        onTap: () => _editProfile(null),
      ),
    ];
    return _section(context, title: '用户档案', rows: rows);
  }

  // ---------------------------------------------------------------------------
  // 数据
  // ---------------------------------------------------------------------------

  Future<void> _exportBackup() async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final json = await widget.services.backups.exportAll();
      await widget.services.exports.shareTextFile(
        fileName: 'deepsleep-backup-${fileTimestamp(DateTime.now())}.json',
        content: json,
        mimeType: 'application/json',
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('备份文件已生成，可在分享面板中保存')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('导出备份失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importBackup() async {
    if (_importing) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('无法读取所选文件')),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _importing = true);
      final content = utf8.decode(bytes);
      final summary = await widget.services.backups.importAll(content);
      await widget.services.conversations.load();
      await widget.services.settings.reloadProfiles();
      await widget.services.memories.refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：${summary.conversations} 个对话 · '
            '${summary.messages} 条消息 · ${summary.memories} 条记忆',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('导入备份失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clearAllConversations() async {
    final confirmed = await _confirm(
      title: '清空全部对话',
      message: '将删除本机全部对话与消息，删除后不可恢复。'
          '\n\n用户档案与记忆不会被删除。',
      confirmLabel: '清空',
    );
    if (!confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.services.database.deleteAllConversations();
    await widget.services.conversations.load();
    messenger.showSnackBar(
      const SnackBar(content: Text('已清空全部对话')),
    );
  }

  Future<void> _clearCurrentMemories() async {
    final profile = widget.services.settings.activeProfile;
    final confirmed = await _confirm(
      title: '清空当前用户记忆',
      message: '将删除「${profile.name}」的全部记忆与知识图谱，删除后不可恢复。',
      confirmLabel: '清空',
    );
    if (!confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.services.memories.clearAll();
    messenger.showSnackBar(
      const SnackBar(content: Text('已清空当前用户的记忆')),
    );
  }

  Widget _buildDataSection(BuildContext context) {
    return _section(
      context,
      title: '数据',
      footnote: '备份为 JSON 文件，包含对话、消息、记忆与用户档案（不含 API Key）。',
      rows: <Widget>[
        _actionRow(
          context,
          label: _exporting ? '正在导出…' : '导出备份',
          onTap: _exportBackup,
          loading: _exporting,
        ),
        _actionRow(
          context,
          label: _importing ? '正在导入…' : '导入备份',
          onTap: _importBackup,
          loading: _importing,
        ),
        _actionRow(
          context,
          label: '清空全部对话',
          onTap: _clearAllConversations,
          danger: true,
        ),
        _actionRow(
          context,
          label: '清空当前用户记忆',
          onTap: _clearCurrentMemories,
          danger: true,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 关于
  // ---------------------------------------------------------------------------

  Widget _buildAboutSection(BuildContext context) {
    return _section(
      context,
      title: '关于',
      footnote: '${AppInfo.appName}（${AppInfo.appNameCn}）以 MIT 许可证开源，'
          '需保留版权与许可声明。免责声明：${AppInfo.disclaimer}。',
      rows: <Widget>[
        _row(context, label: '版本', valueText: 'v${AppInfo.version}'),
        _row(
          context,
          label: 'GitHub 仓库',
          onTap: () => _openUrl(AppInfo.repoUrl),
          trailing: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.open_in_new,
              size: 15,
              color: context.colors.textTertiary,
            ),
          ),
        ),
        _row(
          context,
          label: '开源许可',
          valueText: 'MIT',
          onTap: () => _openUrl(AppInfo.repoUrl),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListenableBuilder(
            listenable: widget.services.settings,
            builder: (context, _) {
              final settings = widget.services.settings.settings;
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: <Widget>[
                  _buildApiSection(context),
                  _buildChatSection(context, settings),
                  _buildSearchSection(context, settings),
                  _buildMemorySection(context, settings),
                  _buildContextSection(context, settings),
                  _buildAppearanceSection(context, settings),
                  _buildProfilesSection(context),
                  _buildDataSection(context),
                  _buildAboutSection(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 用户档案编辑对话框
// -----------------------------------------------------------------------------

class _ProfileDraft {
  const _ProfileDraft({
    required this.name,
    required this.emoji,
    required this.persona,
  });

  final String name;
  final String emoji;
  final String persona;
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({super.key, this.profile});

  final UserProfile? profile;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.profile != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑用户档案' : '新增用户档案'),
      content: SingleChildScrollView(
        child: Column(
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
              decoration: const InputDecoration(
                labelText: '人设（可选）',
                hintText: '例如：回答尽量简短，称呼我为「老板」。',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nameController,
          builder: (context, value, _) {
            final name = value.text.trim();
            return FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                        _ProfileDraft(
                          name: name,
                          emoji: _emojiController.text.trim().isEmpty
                              ? '🧑'
                              : _emojiController.text.trim(),
                          persona: _personaController.text.trim(),
                        ),
                      ),
              child: const Text('保存'),
            );
          },
        ),
      ],
    );
  }
}
