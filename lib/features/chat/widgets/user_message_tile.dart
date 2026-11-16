/// 用户消息：右对齐浅色气泡 + 附件，点击 / 长按可复制或编辑重发。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../state/conversation_controller.dart';
import '../../../widgets/soft_modal.dart';
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
    final result = await showSoftInputDialog(
      context: context,
      title: '编辑消息',
      description: '会删除该消息之后的回复，并重新生成',
      initialValue: message.displayContent,
      hintText: '输入消息内容',
      confirmLabel: '发送',
      maxLines: 6,
    );
    if (result == null || result.trim().isEmpty) return;
    await controller.editUserMessage(message.id, result);
  }
}
