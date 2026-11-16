/// 其他设置：语音、记忆、上下文、数据导入导出与关于。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/profile_models.dart';
import '../../services/history_transfer_service.dart';
import '../../state/app_services.dart';
import '../../widgets/soft_modal.dart';
import 'settings_shared.dart';

class OtherSettingsPage extends StatefulWidget {
  const OtherSettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<OtherSettingsPage> createState() => _OtherSettingsPageState();
}

class _OtherSettingsPageState extends State<OtherSettingsPage> {
  late final TextEditingController _mem0UrlController;
  late final TextEditingController _mem0KeyController;
  late final TextEditingController _searchKeyController;

  bool _obscureMem0Key = true;
  bool _obscureSearchKey = true;
  bool _importing = false;
  bool _exporting = false;
  double _compressThreshold = AppInfo.defaultCompressThreshold.toDouble();
  double _memoryBudget = AppInfo.memoryTokenBudget.toDouble();

  static const List<({String id, String label})> _voices =
      <({String id, String label})>[
    (id: 'stella', label: 'Stella（默认）'),
    (id: 'nana', label: 'Nana'),
    (id: 'claire', label: 'Claire'),
    (id: 'mimi', label: 'Mimi'),
  ];

  @override
  void initState() {
    super.initState();
    final controller = widget.services.settings;
    final settings = controller.settings;
    _mem0UrlController = TextEditingController(text: settings.mem0ApiUrl);
    _mem0KeyController = TextEditingController(text: controller.mem0ApiKey);
    _searchKeyController =
        TextEditingController(text: controller.searchApiKey);
    _compressThreshold = settings.compressThreshold
        .clamp(2000, 12000)
        .toDouble();
    _memoryBudget = settings.memoryTokenBudget
        .clamp(200, 1200)
        .toDouble();
  }

  @override
  void dispose() {
    _mem0UrlController.dispose();
    _mem0KeyController.dispose();
    _searchKeyController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 通用
  // ---------------------------------------------------------------------------

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('打开链接失败：$error')));
    }
  }

  // ---------------------------------------------------------------------------
  // 记忆
  // ---------------------------------------------------------------------------

  Future<void> _changeMemoryBackend(MemoryBackend backend) async {
    final controller = widget.services.settings;
    if (backend == controller.settings.memoryBackend) return;
    if (backend == MemoryBackend.mem0) {
      final agreed = await showSoftConfirm(
        context: context,
        title: '实验性功能',
        description: 'mem0 云平台适配仍处于实验阶段，可能无法正常工作。'
            '\n\n切换后本地记忆网仍然保留，可随时切回。',
        confirmLabel: '仍要切换',
      );
      if (!agreed) return;
    }
    await controller.update(
      controller.settings.copyWith(memoryBackend: backend),
    );
    if (!mounted) return;
    _toast(backend == MemoryBackend.mem0
        ? '已切换到 mem0 云平台（实验性）'
        : '已切换到本地知识网');
  }

  Future<void> _saveMem0Config() async {
    final controller = widget.services.settings;
    final url = _mem0UrlController.text.trim();
    await controller.update(
      controller.settings.copyWith(
        mem0ApiUrl: url.isEmpty ? 'https://api.mem0.ai' : url,
      ),
    );
    await controller.setMem0ApiKey(_mem0KeyController.text);
    if (!mounted) return;
    _toast('mem0 配置已保存');
  }

  // ---------------------------------------------------------------------------
  // 数据：本应用备份
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
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出备份失败：$error')));
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
      final summary =
          await widget.services.backups.importAll(utf8.decode(bytes));
      await _reloadAll();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：${summary.conversations} 个对话 · '
            '${summary.messages} 条消息 · ${summary.memories} 条记忆',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导入备份失败：$error')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 数据：DeepSeek 历史 ZIP
  // ---------------------------------------------------------------------------

  Future<Uint8List?> _pickZip() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    if (!mounted) return null;
    final preview = await widget.services.historyTransfer.preview(
      bytes,
      file.name,
    );
    if (!mounted) return null;
    if (!preview.ok) {
      await showSoftDialog<void>(
        context: context,
        title: '无法识别该文件',
        description: preview.error ?? '请选择 DeepSeek 导出的 .zip 历史对话文件。',
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
      return null;
    }
    final agreed = await _showImportPreview(preview);
    if (!agreed) return null;
    setState(() => _importing = true);
    return bytes;
  }

  Future<bool> _showImportPreview(HistoryImportPreview preview) async {
    final colors = context.colors;
    final result = await showSoftDialog<bool>(
      context: context,
      title: '导入 DeepSeek 历史',
      description: '格式：${preview.format.isEmpty ? '未知' : preview.format}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _previewLine('对话', '${preview.conversations} 个'),
          _previewLine('消息', '${preview.messages} 条'),
          _previewLine('附件', '${preview.attachments} 个'),
          _previewLine('冲突', '${preview.conflicts} 个'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '导入会合并到现有数据，不覆盖已有对话。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('开始导入'),
        ),
      ],
    );
    return result ?? false;
  }

  Widget _previewLine(String label, String value) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  Future<void> _importDeepSeekZip() async {
    if (_importing) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _pickZip();
      if (bytes == null) return;
      final message = await widget.services.historyTransfer.importDeepSeekZip(
        bytes,
        replace: false,
      );
      await _reloadAll();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$error')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportDeepSeekZip() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.services.historyTransfer.exportDeepSeekZip();
      final directory = await getTemporaryDirectory();
      final fileName =
          'deepsleep-deepseek-${fileTimestamp(DateTime.now())}.zip';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'application/zip')],
        subject: fileName,
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  Future<void> _reloadAll() async {
    await widget.services.conversations.load();
    await widget.services.settings.reloadProfiles();
    await widget.services.memories.refresh();
  }

  Future<void> _clearAllConversations() async {
    final confirmed = await showSoftConfirm(
      context: context,
      title: '清空全部对话',
      description: '将删除本机全部对话与消息，删除后不可恢复。'
          '\n\n用户档案与记忆不会被删除。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.services.database.deleteAllConversations();
    await widget.services.conversations.load();
    messenger.showSnackBar(const SnackBar(content: Text('已清空全部对话')));
  }

  Future<void> _clearCurrentMemories() async {
    final profile = widget.services.settings.activeProfile;
    final confirmed = await showSoftConfirm(
      context: context,
      title: '清空当前用户记忆',
      description: '将删除「${profile.name}」的全部记忆与知识图谱，删除后不可恢复。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.services.memories.clearAll();
    messenger.showSnackBar(
      const SnackBar(content: Text('已清空当前用户的记忆')),
    );
  }

  Future<void> _saveSearchKey() async {
    await widget.services.settings
        .setSearchApiKey(_searchKeyController.text);
    if (!mounted) return;
    _toast('搜索 API Key 已保存');
  }

  String _searchBackendLabel(SearchBackend backend) {
    switch (backend) {
      case SearchBackend.off:
        return '关闭';
      case SearchBackend.deepseek:
        return 'DeepSeek 内置搜索';
      case SearchBackend.tavily:
        return 'Tavily';
      case SearchBackend.serper:
        return 'Serper';
    }
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.services.settings,
      builder: (context, _) {
        final settings = widget.services.settings.settings;
        return SettingsScaffold(
          title: '其他',
          children: <Widget>[
            _buildChatSearchSection(context, settings),
            _buildVoiceSection(context, settings),
            _buildMemorySection(context, settings),
            _buildContextSection(context, settings),
            _buildDataSection(context),
            _buildAboutSection(context),
          ],
        );
      },
    );
  }

  Widget _buildChatSearchSection(
    BuildContext context,
    AppSettings settings,
  ) {
    final showKey = settings.searchBackend == SearchBackend.tavily ||
        settings.searchBackend == SearchBackend.serper;
    return SettingsSection(
      title: '对话与搜索',
      footnote: showKey
          ? 'Tavily / Serper 的 Key 可在 tavily.com、serper.dev 免费申请。'
          : null,
      rows: <Widget>[
        SettingsSwitchRow(
          label: '深度思考',
          value: settings.deepThinking,
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(deepThinking: value)),
        ),
        SettingsSwitchRow(
          label: 'Enter 发送',
          value: settings.sendWithEnter,
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(sendWithEnter: value)),
        ),
        SettingsSwitchRow(
          label: '显示 token 用量',
          value: settings.showTokenUsage,
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(showTokenUsage: value)),
        ),
        SettingsDropdownRow<SearchBackend>(
          label: '搜索服务商',
          value: settings.searchBackend,
          items: <DropdownMenuItem<SearchBackend>>[
            for (final backend in SearchBackend.values)
              DropdownMenuItem<SearchBackend>(
                value: backend,
                child: Text(_searchBackendLabel(backend)),
              ),
          ],
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(searchBackend: value)),
        ),
        if (showKey) ...<Widget>[
          SettingsInputRow(
            label: '搜索 API Key',
            controller: _searchKeyController,
            hint: settings.searchBackend == SearchBackend.serper
                ? 'serper.dev 的 Key'
                : 'tvly-...',
            obscured: _obscureSearchKey,
            onToggleObscure: () =>
                setState(() => _obscureSearchKey = !_obscureSearchKey),
          ),
          SettingsActionRow(label: '保存搜索 Key', onTap: _saveSearchKey),
        ],
      ],
    );
  }

  Widget _buildVoiceSection(BuildContext context, AppSettings settings) {
    return SettingsSection(
      title: '语音',
      footnote: '语音能力仅保存设置，具体朗读效果取决于设备与接口支持。',
      rows: <Widget>[
        SettingsSwitchRow(
          label: '朗读回复',
          value: settings.ttsEnabled,
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(ttsEnabled: value)),
        ),
        SettingsDropdownRow<String>(
          label: '朗读音色',
          value: _voices.any((voice) => voice.id == settings.ttsVoice)
              ? settings.ttsVoice
              : 'stella',
          items: <DropdownMenuItem<String>>[
            for (final voice in _voices)
              DropdownMenuItem<String>(
                value: voice.id,
                child: Text(voice.label),
              ),
          ],
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(ttsVoice: value)),
        ),
        SettingsSwitchRow(
          label: '语音输入',
          value: settings.voiceInputEnabled,
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(voiceInputEnabled: value)),
        ),
      ],
    );
  }

  Widget _buildMemorySection(BuildContext context, AppSettings settings) {
    final isMem0 = settings.memoryBackend == MemoryBackend.mem0;
    return SettingsSection(
      title: '记忆',
      footnote: isMem0 ? 'mem0 为实验性选项，需联网写入云端。' : null,
      rows: <Widget>[
        SettingsSwitchRow(
          label: '长期记忆',
          value: settings.memoryEnabled,
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(memoryEnabled: value)),
        ),
        SettingsSwitchRow(
          label: '自动抽取记忆',
          value: settings.autoExtractMemory,
          onChanged: (value) => widget.services.settings
              .update(settings.copyWith(autoExtractMemory: value)),
        ),
        SettingsDropdownRow<MemoryBackend>(
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
          SettingsInputRow(
            label: 'mem0 API URL',
            controller: _mem0UrlController,
            hint: 'https://api.mem0.ai',
            keyboardType: TextInputType.url,
          ),
          SettingsInputRow(
            label: 'mem0 API Key',
            controller: _mem0KeyController,
            hint: 'm0-...',
            obscured: _obscureMem0Key,
            onToggleObscure: () =>
                setState(() => _obscureMem0Key = !_obscureMem0Key),
          ),
          SettingsActionRow(label: '保存 mem0 配置', onTap: _saveMem0Config),
        ],
      ],
    );
  }

  Widget _buildContextSection(BuildContext context, AppSettings settings) {
    return SettingsSection(
      title: '上下文',
      footnote: '阈值越小越省 token，但更快丢失细节；记忆预算越大越「记得多」。',
      rows: <Widget>[
        SettingsSliderRow(
          label: '上下文压缩阈值',
          valueText: '${_compressThreshold.round()} tokens',
          value: _compressThreshold,
          min: 2000,
          max: 12000,
          divisions: 20,
          onChanged: (value) => setState(() => _compressThreshold = value),
          onChangeEnd: (value) => widget.services.settings.update(
            settings.copyWith(compressThreshold: value.round()),
          ),
        ),
        SettingsSliderRow(
          label: '记忆注入预算',
          valueText: '${_memoryBudget.round()} tokens',
          value: _memoryBudget,
          min: 200,
          max: 1200,
          divisions: 20,
          onChanged: (value) => setState(() => _memoryBudget = value),
          onChangeEnd: (value) => widget.services.settings.update(
            settings.copyWith(memoryTokenBudget: value.round()),
          ),
        ),
      ],
    );
  }

  Widget _buildDataSection(BuildContext context) {
    return SettingsSection(
      title: '数据',
      footnote: 'DeepSeek ZIP 用于与其他 DeepSeek 客户端互通；本应用备份包含全部本地数据。',
      rows: <Widget>[
        SettingsActionRow(
          label: '导入 DeepSeek 历史（ZIP）',
          loading: _importing,
          onTap: _importDeepSeekZip,
        ),
        SettingsActionRow(
          label: '导出 DeepSeek 历史（ZIP）',
          onTap: _exportDeepSeekZip,
        ),
        SettingsActionRow(
          label: '导出本应用备份',
          loading: _exporting,
          onTap: _exportBackup,
        ),
        SettingsActionRow(
          label: '导入本应用备份',
          loading: _importing,
          onTap: _importBackup,
        ),
        SettingsActionRow(
          label: '清空全部对话',
          danger: true,
          onTap: _clearAllConversations,
        ),
        SettingsActionRow(
          label: '清空当前用户记忆',
          danger: true,
          onTap: _clearCurrentMemories,
        ),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final colors = context.colors;
    return SettingsSection(
      title: '关于',
      footnote: '${AppInfo.appName}（${AppInfo.appNameCn}）以 MIT 许可证开源，'
          '需保留版权与许可声明。免责声明：${AppInfo.disclaimer}。',
      rows: <Widget>[
        SettingsRow(label: '版本', valueText: 'v${AppInfo.version}'),
        SettingsRow(
          label: 'GitHub 仓库',
          onTap: () => _openUrl(AppInfo.repoUrl),
          trailing: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.open_in_new,
              size: 15,
              color: colors.textTertiary,
            ),
          ),
        ),
        SettingsRow(
          label: '开源许可',
          valueText: 'MIT',
          onTap: () => _openUrl(AppInfo.repoUrl),
        ),
      ],
    );
  }
}
