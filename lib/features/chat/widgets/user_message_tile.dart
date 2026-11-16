/// 用户消息：右对齐浅色气泡 + 附件，点击 / 长按可复制或编辑重发。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../state/conversation_controller.dart';
import 'attachment_preview.dart';

class UserMessageTile extends StatelessWidget {
  const UserMessageTile({
    super.key,
    required this.message,
    required this.controller,
  });

  final ChatMessage message;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final attachments = message.attachments;
    final content = message.displayContent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = MediaQuery.sizeOf(context).width < 440;
        final rawMax = constraints.maxWidth - (narrow ? 68 : 88);
        final bubbleMax = rawMax < 80 ? 80.0 : rawMax;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bubbleMax),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          for (final attachment in attachments)
                            AttachmentChip(attachment: attachment),
                        ],
                      ),
                    ),
                  if (content.trim().isNotEmpty)
                    GestureDetector(
                      onTap: () => _showMenu(context),
                      onLongPress: () => _showMenu(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.userBubble,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          content,
                          style: TextStyle(
                            fontSize: 16,
                            height: 24 / 16,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final colors = context.colors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.bgElevated,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  Icons.copy_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
                title: Text(
                  '复制',
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _copy(context);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: colors.textSecondary,
                ),
                title: Text(
                  '编辑后重新发送',
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
                subtitle: Text(
                  '会删除该消息之后的回复',
                  style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _edit(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copy(BuildContext context) async {
    final text = message.displayContent;
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  Future<void> _edit(BuildContext context) async {
    if (controller.streaming) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在生成回复，请稍后再编辑')),
      );
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _EditMessageDialog(
        initialText: message.displayContent,
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    await controller.editUserMessage(message.id, result);
  }
}

class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        '编辑消息',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: TextField(
          controller: _textController,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: colors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '输入消息内容',
            filled: false,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: colors.border),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_textController.text),
          child: const Text('发送'),
        ),
      ],
    );
  }
}
