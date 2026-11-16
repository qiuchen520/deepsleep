/// 消息列表：按角色分派到用户气泡 / 助手 Markdown 消息，内容区最大宽度 780。
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

  static const double maxContentWidth = 780;

  @override
  Widget build(BuildContext context) {
    final messages = controller.messages;
    final lastAssistantId = controller.lastAssistantMessage?.id;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _MessageBody(
                message: message,
                controller: controller,
                isLastAssistant: isLastAssistant,
                isStreaming: isStreaming,
              ),
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
      return Center(
        child: Text(
          message.displayContent,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
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
