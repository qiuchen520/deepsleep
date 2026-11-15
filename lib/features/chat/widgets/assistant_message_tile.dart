/// 助手消息：搜索来源卡片 + 思考面板 + Markdown 正文 + 操作行（复制 / 重新
/// 生成 / 继续生成 / 版本切换）+ 记忆引用 + 失败重试。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../state/conversation_controller.dart';
import '../../../widgets/markdown_view.dart';
import 'error_card.dart';
import 'memory_citation_chip.dart';
import 'search_hits_card.dart';
import 'streaming_indicator.dart';
import 'thinking_panel.dart';

class AssistantMessageTile extends StatelessWidget {
  const AssistantMessageTile({
    super.key,
    required this.message,
    required this.controller,
    required this.isLastAssistant,
    required this.isStreaming,
  });

  final ChatMessage message;
  final ConversationController controller;

  /// 是否是会话里最后一条助手消息（决定是否展示重新生成 / 继续生成）。
  final bool isLastAssistant;

  /// 这条消息是否正在流式生成。
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reasoning = message.displayReasoning;
    final content = message.displayContent;
    final hasReasoning = reasoning.trim().isNotEmpty;
    final hasContent = content.trim().isNotEmpty;
    final failed = message.isFailed;
    final canContinue = isLastAssistant &&
        (message.status == MessageStatus.stopped ||
            message.status == MessageStatus.done);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (message.searchHits.isNotEmpty)
          SearchHitsCard(hits: message.searchHits),
        if (hasReasoning)
          ThinkingPanel(
            reasoning: reasoning,
            streaming: isStreaming && message.isStreaming,
            startedAt: message.createdAt,
            finishedAt: message.finishedAt,
          ),
        if (hasContent) MarkdownView(data: content),
        if (isStreaming && hasContent)
          const Align(
            alignment: Alignment.centerLeft,
            child: StreamingCursor(),
          ),
        if (isStreaming && !hasContent && !hasReasoning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: TypingDots(size: 7),
          ),
        if (failed)
          ErrorCard(
            message: message.error ?? controller.lastError ?? '生成失败，请重试',
            onRetry: controller.regenerateLast,
          ),
        if (!isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _IconAction(
                  icon: Icons.copy_rounded,
                  tooltip: '复制',
                  onTap: hasContent ? () => _copy(context) : null,
                ),
                if (isLastAssistant && !failed)
                  _IconAction(
                    icon: Icons.refresh_rounded,
                    tooltip: '重新生成',
                    onTap: () => controller.regenerateLast(),
                  ),
                if (canContinue)
                  _IconAction(
                    icon: Icons.play_arrow_rounded,
                    tooltip: '继续生成',
                    onTap: () => controller.continueGeneration(),
                  ),
                if (message.hasVersions)
                  _VersionSwitcher(message: message, controller: controller),
              ],
            ),
          ),
        if (!isStreaming && message.citedMemoryIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MemoryCitationChip(
              citedMemoryIds: message.citedMemoryIds,
              controller: controller,
            ),
          ),
        if (message.compressed && !isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '此条较早的消息已被压缩为上下文摘要',
              style: TextStyle(fontSize: 10.5, color: colors.textTertiary),
            ),
          ),
      ],
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
}

class _VersionSwitcher extends StatelessWidget {
  const _VersionSwitcher({required this.message, required this.controller});

  final ChatMessage message;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = message.activeVersion < 0
        ? message.versions.length
        : message.activeVersion;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _IconAction(
          icon: Icons.chevron_left_rounded,
          tooltip: '上一版本',
          onTap: current > 0
              ? () => controller.selectVersion(message.id, current - 1)
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '${current + 1}/${message.versionCount}',
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ),
        _IconAction(
          icon: Icons.chevron_right_rounded,
          tooltip: '下一版本',
          onTap: current < message.versionCount - 1
              ? () => controller.selectVersion(message.id, current + 1)
              : null,
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final color = enabled
        ? colors.textTertiary
        : colors.textTertiary.withValues(alpha: 0.35);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
