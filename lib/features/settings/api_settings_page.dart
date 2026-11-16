/// API 设置：Base URL、模型、API Key、验证与充值。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../services/contracts.dart';
import '../../state/app_services.dart';
import 'settings_shared.dart';

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _chatModelController;
  late final TextEditingController _reasonerModelController;
  late final TextEditingController _apiKeyController;

  bool _obscureApiKey = true;
  bool _validating = false;

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
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _chatModelController.dispose();
    _reasonerModelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _save() async {
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
    if (!mounted) return;
    _toast('API 配置已保存');
  }

  Future<void> _validate() async {
    if (_apiKeyController.text.trim().isEmpty) {
      _toast('请先填写 API Key');
      return;
    }
    setState(() => _validating = true);
    try {
      await widget.services.settings.setApiKey(_apiKeyController.text);
      await widget.services.api.validateApiKey();
      if (!mounted) return;
      _toast('API Key 验证通过');
    } catch (error) {
      if (!mounted) return;
      final message =
          error is ApiException ? error.friendlyMessage : '验证失败：$error';
      _toast(message);
    } finally {
      if (mounted) setState(() => _validating = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'API',
      children: <Widget>[
        SettingsSection(
          title: '连接',
          rows: <Widget>[
            SettingsInputRow(
              label: 'Base URL',
              controller: _baseUrlController,
              hint: AppInfo.defaultBaseUrl,
              keyboardType: TextInputType.url,
            ),
            SettingsInputRow(
              label: '对话模型',
              controller: _chatModelController,
              hint: AppInfo.defaultChatModel,
            ),
            SettingsInputRow(
              label: '推理模型',
              controller: _reasonerModelController,
              hint: AppInfo.defaultReasonerModel,
            ),
          ],
        ),
        SettingsSection(
          title: '凭据',
          footnote: 'Key 保存在系统安全存储中，不写入备份文件。',
          rows: <Widget>[
            SettingsInputRow(
              label: 'API Key',
              controller: _apiKeyController,
              hint: 'sk-...',
              obscured: _obscureApiKey,
              onToggleObscure: () =>
                  setState(() => _obscureApiKey = !_obscureApiKey),
            ),
          ],
        ),
        SettingsSection(
          title: '操作',
          rows: <Widget>[
            SettingsActionRow(label: '保存 API 配置', onTap: _save),
            SettingsActionRow(
              label: '验证 API Key',
              loading: _validating,
              onTap: _validate,
            ),
            SettingsActionRow(
              label: '前往充值',
              onTap: () =>
                  _openUrl('https://platform.deepseek.com/top_up'),
            ),
          ],
        ),
      ],
    );
  }
}
