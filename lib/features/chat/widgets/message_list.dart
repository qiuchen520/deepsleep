/// 消息列表：按角色分派到用户气泡 / 助手 Markdown 消息。
///
/// 对齐 docs/UI_SPEC.md：内容区最大宽度 840（实际内容列 752），桌面左右内边距
/// 44、窄屏（<600）16；列表顶部 34、底部 24；消息间距由各消息容器负责
/// （用户容器 padding-bottom 16，助手底部含操作栏）。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../state/conversation_controller.dart';
import 'assistant_message_tile.dart';
import 'user_message_tile.dart';

class MessageList extends StatelessWidget {
  const MessageList({
    super.key,
    required this.controller,
    required this.scrollController,
  });

  final ConversationController controller;
  final ScrollController scrollController;

  /// 规格：消息内容区最大 840，扣掉左右 44 后内容列 752。
  static const double maxWidth = 840;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 600 ? 16.0 : 44.0;
    final contentMaxWidth = maxWidth - horizontal * 2;
    final messages = controller.messages;
    final lastAssistantId = controller.lastAssistantMessage?.id;
    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(horizontal, 34, horizontal, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isLast = index == messages.length - 1;
        final isLastAssistant =
            message.role == MessageRole.assistant &&
            message.id == lastAssistantId;
        final isStreaming =
            controller.streaming && message.isStreaming && isLast;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: _MessageBody(
              message: message,
              controller: controller,
              isLastAssistant: isLastAssistant,
              isStreaming: isStreaming,
            ),
          ),
        );
      },
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.message,
    required this.controller,
    required this.isLastAssistant,
    required this.isStreaming,
  });

  final ChatMessage message;
  final ConversationController controller;
  final bool isLastAssistant;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.system) {
      final colors = context.colors;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Center(
          child: Text(
            message.displayContent,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ),
      );
    }
    if (message.role == MessageRole.user) {
      return UserMessageTile(message: message, controller: controller);
    }
    return AssistantMessageTile(
      message: message,
      controller: controller,
      isLastAssistant: isLastAssistant,
      isStreaming: isStreaming,
    );
  }
}
