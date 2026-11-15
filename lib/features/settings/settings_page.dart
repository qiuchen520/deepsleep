/// 设置页：API 配置、对话偏好、记忆设置、外观、用户档案、数据备份与关于。
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
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.danger,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Widget _card(
    BuildContext context, {
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _secretField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required bool obscured,
    required VoidCallback onToggle,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        obscureText: obscured,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: IconButton(
            tooltip: obscured ? '显示' : '隐藏',
            onPressed: onToggle,
            iconSize: 18,
            icon: Icon(
              obscured
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.sm),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.5,
          color: context.colors.textTertiary,
        ),
      ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(fontSize: 14, color: context.colors.textPrimary),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                color: context.colors.textTertiary,
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _choiceRow<T>(
    BuildContext context, {
    required String label,
    required T value,
    required List<({T value, String label})> options,
    required ValueChanged<T> onChanged,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final option in options)
                ChoiceChip(
                  label: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: value == option.value
                          ? colors.brandText
                          : colors.textSecondary,
                    ),
                  ),
                  selected: value == option.value,
                  showCheckmark: false,
                  selectedColor: colors.brandSoft,
                  backgroundColor: colors.bgBase,
                  side: BorderSide(
                    color: value == option.value
                        ? colors.brand
                        : colors.border,
                  ),
                  onSelected: (selected) {
                    if (!selected) return;
                    onChanged(option.value);
                  },
                ),
            ],
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

  Widget _buildApiCard(BuildContext context) {
    return _card(
      context,
      title: 'API 配置',
      subtitle: '使用 DeepSeek 开放平台（OpenAI 兼容接口）',
      children: <Widget>[
        _field(
          context,
          label: 'Base URL',
          controller: _baseUrlController,
          hint: AppInfo.defaultBaseUrl,
          keyboardType: TextInputType.url,
        ),
        _field(
          context,
          label: '对话模型',
          controller: _chatModelController,
          hint: AppInfo.defaultChatModel,
        ),
        _field(
          context,
          label: '深度思考模型',
          controller: _reasonerModelController,
          hint: AppInfo.defaultReasonerModel,
        ),
        _secretField(
          context,
          label: 'API Key',
          controller: _apiKeyController,
          obscured: _obscureApiKey,
          hint: 'sk-...',
          onToggle: () => setState(() => _obscureApiKey = !_obscureApiKey),
        ),
        _hint(context, 'Key 保存在系统安全存储中，不写入备份文件。'),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: _saveApiConfig,
                child: const Text('保存 API 配置'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            OutlinedButton(
              onPressed: _validating ? null : _validateApiKey,
              child: _validating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('验证'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                _openUrl('https://platform.deepseek.com/top_up'),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('前往充值'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 对话设置
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
    if (backend != SearchBackend.off &&
        controller.searchApiKey.trim().isEmpty) {
      if (!mounted) return;
      _toast('已开启${_searchBackendLabel(backend)}搜索，请填写搜索 API Key');
    }
  }

  String _searchBackendLabel(SearchBackend backend) {
    switch (backend) {
      case SearchBackend.off:
        return '关闭';
      case SearchBackend.tavily:
        return 'Tavily';
      case SearchBackend.serper:
        return 'Serper';
    }
  }

  Widget _buildChatCard(BuildContext context, AppSettings settings) {
    final colors = context.colors;
    return _card(
      context,
      title: '对话',
      children: <Widget>[
        _switchTile(
          context,
          title: '默认开启深度思考',
          subtitle: '使用 Reasoner 模型并展示思考过程',
          value: settings.deepThinking,
          onChanged: (value) => _update(
            settings.copyWith(deepThinking: value),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Text(
              '联网搜索',
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
            ),
            const Spacer(),
            DropdownButton<SearchBackend>(
              value: settings.searchBackend,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
              items: <DropdownMenuItem<SearchBackend>>[
                for (final backend in SearchBackend.values)
                  DropdownMenuItem<SearchBackend>(
                    value: backend,
                    child: Text(_searchBackendLabel(backend)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _changeSearchBackend(value);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _secretField(
          context,
          label: '搜索 API Key',
          controller: _searchKeyController,
          obscured: _obscureSearchKey,
          hint: settings.searchBackend == SearchBackend.serper
              ? 'serper.dev 的 API Key'
              : 'tvly-...',
          onToggle: () =>
              setState(() => _obscureSearchKey = !_obscureSearchKey),
        ),
        _hint(
          context,
          'Tavily 可在 tavily.com 免费申请 Key，Serper 可在 serper.dev 申请；两者共用此输入框。',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _saveSearchKey,
            child: const Text('保存搜索 Key'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _switchTile(
          context,
          title: '显示 token 用量',
          subtitle: '在消息下方展示上下文与消耗估算',
          value: settings.showTokenUsage,
          onChanged: (value) => _update(
            settings.copyWith(showTokenUsage: value),
          ),
        ),
        _switchTile(
          context,
          title: '使用 Enter 发送',
          subtitle: '关闭后 Enter 换行，改用发送按钮提交',
          value: settings.sendWithEnter,
          onChanged: (value) => _update(
            settings.copyWith(sendWithEnter: value),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 记忆设置
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

  Widget _buildMemoryCard(BuildContext context, AppSettings settings) {
    final colors = context.colors;
    return _card(
      context,
      title: '记忆',
      subtitle: '长期记忆会沉淀成知识网，跨对话提供个性化上下文',
      children: <Widget>[
        _switchTile(
          context,
          title: '开启长期记忆',
          value: settings.memoryEnabled,
          onChanged: (value) => _update(
            settings.copyWith(memoryEnabled: value),
          ),
        ),
        _switchTile(
          context,
          title: '自动抽取记忆',
          subtitle: '每轮回复结束后自动抽取事实、偏好与事件',
          value: settings.autoExtractMemory,
          onChanged: (value) => _update(
            settings.copyWith(autoExtractMemory: value),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Text(
              '记忆后端',
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
            ),
            const Spacer(),
            DropdownButton<MemoryBackend>(
              value: settings.memoryBackend,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
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
              onChanged: (value) {
                if (value == null) return;
                _changeMemoryBackend(value);
              },
            ),
          ],
        ),
        _hint(
          context,
          'mem0 为实验性选项；本地知识网无需联网，数据只存在本机数据库。',
        ),
        _field(
          context,
          label: 'mem0 API URL',
          controller: _mem0UrlController,
          hint: 'https://api.mem0.ai',
          keyboardType: TextInputType.url,
        ),
        _secretField(
          context,
          label: 'mem0 API Key',
          controller: _mem0KeyController,
          obscured: _obscureMem0Key,
          hint: 'm0-...',
          onToggle: () => setState(() => _obscureMem0Key = !_obscureMem0Key),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _saveMem0Config,
            child: const Text('保存 mem0 配置'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '上下文压缩阈值',
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
              ),
            ),
            Text(
              '${_compressThreshold.round()} tokens',
              style: TextStyle(fontSize: 12.5, color: colors.textTertiary),
            ),
          ],
        ),
        Slider(
          value: _compressThreshold,
          min: 2000,
          max: 12000,
          divisions: 20,
          label: '${_compressThreshold.round()}',
          onChanged: (value) => setState(() => _compressThreshold = value),
          onChangeEnd: (value) => _update(
            settings.copyWith(compressThreshold: value.round()),
          ),
        ),
        _hint(
          context,
          '上下文估算超过该 token 数时，自动把较早的对话压缩成摘要，'
          '保留最近若干条原文。调小更省 token，但会更快丢失细节。',
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '记忆注入预算',
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
              ),
            ),
            Text(
              '${_memoryBudget.round()} tokens',
              style: TextStyle(fontSize: 12.5, color: colors.textTertiary),
            ),
          ],
        ),
        Slider(
          value: _memoryBudget,
          min: 200,
          max: 1200,
          divisions: 20,
          label: '${_memoryBudget.round()}',
          onChanged: (value) => setState(() => _memoryBudget = value),
          onChangeEnd: (value) => _update(
            settings.copyWith(memoryTokenBudget: value.round()),
          ),
        ),
        _hint(
          context,
          '每轮最多把该预算内的长期记忆注入 System Prompt。越大越「记得多」，'
          '但会占用更多上下文。',
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

  String _fontScaleLabel(double scale) {
    if (scale <= 0.95) return '小 0.9x';
    if (scale <= 1.05) return '标准 1.0x';
    if (scale <= 1.15) return '大 1.1x';
    return '特大 1.2x';
  }

  Widget _buildAppearanceCard(BuildContext context, AppSettings settings) {
    final colors = context.colors;
    return _card(
      context,
      title: '外观',
      children: <Widget>[
        _choiceRow<ThemePreference>(
          context,
          label: '主题',
          value: settings.theme,
          options: <({ThemePreference value, String label})>[
            for (final preference in ThemePreference.values)
              (value: preference, label: _themeLabel(preference)),
          ],
          onChanged: (value) =>
              _update(settings.copyWith(theme: value)),
        ),
        Text(
          '字号',
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildFontScaleChoices(context, settings),
        _hint(context, '字号缩放会先保存设置，界面缩放将在后续版本生效。'),
      ],
    );
  }

  Widget _buildFontScaleChoices(
    BuildContext context,
    AppSettings settings,
  ) {
    const choices = <double>[0.9, 1.0, 1.1, 1.2];
    final colors = context.colors;
    final current = _nearestFontScale(choices, settings.fontScale);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final choice in choices)
          ChoiceChip(
            label: Text(
              _fontScaleLabel(choice),
              style: TextStyle(
                fontSize: 12.5,
                color: current == choice
                    ? colors.brandText
                    : colors.textSecondary,
              ),
            ),
            selected: current == choice,
            showCheckmark: false,
            selectedColor: colors.brandSoft,
            backgroundColor: colors.bgBase,
            side: BorderSide(
              color: current == choice ? colors.brand : colors.border,
            ),
            onSelected: (selected) {
              if (!selected) return;
              _update(settings.copyWith(fontScale: choice));
            },
          ),
      ],
    );
  }

  double _nearestFontScale(List<double> choices, double value) {
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
      message: '删除后该档案将不再出现在切换列表中（其对话与记忆仍保留在本地数据库）。'
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

  Widget _buildProfilesCard(BuildContext context) {
    final colors = context.colors;
    final controller = widget.services.settings;
    final profiles = controller.profiles;
    final activeId = controller.settings.activeProfileId;
    return _card(
      context,
      title: '用户档案',
      subtitle: '每个档案拥有独立的对话与长期记忆',
      children: <Widget>[
        for (final profile in profiles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(profile.emoji, style: const TextStyle(fontSize: 22)),
            title: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (profile.id == activeId)
                  Container(
                    margin: const EdgeInsets.only(left: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.brandSoft,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '当前',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: colors.brandText,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              profile.persona.trim().isEmpty
                  ? '未设置人设'
                  : profile.persona.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: '编辑档案',
                  iconSize: 18,
                  onPressed: () => _editProfile(profile),
                  icon: Icon(Icons.edit_outlined, color: colors.textSecondary),
                ),
                IconButton(
                  tooltip: '删除档案',
                  iconSize: 18,
                  onPressed: () => _deleteProfile(profile),
                  icon: Icon(
                    Icons.delete_outline,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
            onTap: () => _switchProfile(profile),
          ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _editProfile(null),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新增档案'),
          ),
        ),
      ],
    );
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

  Widget _buildDataCard(BuildContext context) {
    final colors = context.colors;
    return _card(
      context,
      title: '数据',
      subtitle: '备份为 JSON 文件，包含对话、消息、记忆与用户档案（不含 API Key）',
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.upload_file_outlined, color: colors.textSecondary),
          title: Text(
            '导出备份',
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          subtitle: Text(
            '生成 JSON 并调起系统分享',
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
          trailing: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.chevron_right, size: 18, color: colors.textTertiary),
          onTap: _exporting ? null : _exportBackup,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.download_outlined, color: colors.textSecondary),
          title: Text(
            '导入备份',
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          subtitle: Text(
            '从 .json 备份文件恢复数据',
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
          trailing: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.chevron_right, size: 18, color: colors.textTertiary),
          onTap: _importing ? null : _importBackup,
        ),
        Divider(color: colors.border),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_sweep_outlined, color: colors.danger),
          title: Text(
            '清空全部对话',
            style: TextStyle(fontSize: 14, color: colors.danger),
          ),
          onTap: _clearAllConversations,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.psychology_outlined, color: colors.danger),
          title: Text(
            '清空当前用户记忆',
            style: TextStyle(fontSize: 14, color: colors.danger),
          ),
          onTap: _clearCurrentMemories,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 关于
  // ---------------------------------------------------------------------------

  Widget _buildAboutCard(BuildContext context) {
    final colors = context.colors;
    return _card(
      context,
      title: '关于',
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '版本',
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          trailing: Text(
            'v${AppInfo.version}',
            style: TextStyle(fontSize: 13, color: colors.textTertiary),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'GitHub 仓库',
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          subtitle: Text(
            AppInfo.repoUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
          trailing: Icon(
            Icons.open_in_new,
            size: 17,
            color: colors.textSecondary,
          ),
          onTap: () => _openUrl(AppInfo.repoUrl),
        ),
        Divider(color: colors.border),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            '${AppInfo.appName}（${AppInfo.appNameCn}）以 MIT 许可证开源，'
            '你可以自由使用、修改与分发，但需保留版权声明与许可声明。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: colors.textSecondary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            '免责声明：${AppInfo.disclaimer}。本应用与 DeepSeek 官方无隶属关系，'
            'API Key 与产生的费用由用户自行承担。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: colors.textTertiary,
            ),
          ),
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
      body: ListenableBuilder(
        listenable: widget.services.settings,
        builder: (context, _) {
          final settings = widget.services.settings.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              _buildApiCard(context),
              _buildChatCard(context, settings),
              _buildMemoryCard(context, settings),
              _buildAppearanceCard(context, settings),
              _buildProfilesCard(context),
              _buildDataCard(context),
              _buildAboutCard(context),
            ],
          );
        },
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
