/// 助手消息：搜索来源 / 思考折叠 + Markdown 正文 + 操作栏。
///
/// 对齐 docs/UI_SPEC.md：无气泡无头像；正文 16/28（由 MarkdownView 负责）；
/// 正文与操作栏之间 6px，操作栏 padding-top 12 / padding-bottom 10，
/// 图标按钮 28px、间距 10，整体左移 6px 与正文对齐。
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

class AssistantMessageTile extends StatefulWidget {
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
  State<AssistantMessageTile> createState() => _AssistantMessageTileState();
}

class _AssistantMessageTileState extends State<AssistantMessageTile> {
  bool _showActions = false;

  void _toggleActions() {
    if (widget.isLastAssistant || widget.isStreaming) return;
    setState(() => _showActions = !_showActions);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final controller = widget.controller;
    final streaming = widget.isStreaming;
    final reasoning = message.displayReasoning;
    final content = message.displayContent;
    final hasReasoning = reasoning.trim().isNotEmpty;
    final hasContent = content.trim().isNotEmpty;
    final failed = message.isFailed;
    final isLast = widget.isLastAssistant;
    final showActions = (isLast || _showActions) && !streaming;
    final searching =
        streaming && controller.searchOn && message.searchHits.isEmpty;
    final canContinue = isLast &&
        (message.status == MessageStatus.stopped ||
            message.status == MessageStatus.done);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleActions,
      onLongPress: _toggleActions,
      child: Padding(
        padding: EdgeInsets.only(bottom: showActions ? 0.0 : 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (message.searchHits.isNotEmpty || searching)
              SearchHitsCard(hits: message.searchHits, searching: searching),
            if (hasReasoning)
              ThinkingPanel(
                reasoning: reasoning,
                streaming: streaming && message.isStreaming,
                startedAt: message.createdAt,
                finishedAt: message.finishedAt,
              ),
            if (hasContent) MarkdownView(data: content),
            if (streaming && hasContent)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: StreamingCursor(),
              ),
            if (streaming && !hasContent && !hasReasoning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: TypingDots(size: 6),
              ),
            if (failed)
              ErrorCard(
                message:
                    message.error ?? controller.lastError ?? '生成失败，请重试',
                onRetry: controller.regenerateLast,
              ),
            if (!streaming && message.citedMemoryIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MemoryCitationChip(
                  citedMemoryIds: message.citedMemoryIds,
                  controller: controller,
                ),
              ),
            if (showActions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Transform.translate(
                  offset: const Offset(-6, 0),
                  child: Container(
                    padding: const EdgeInsets.only(top: 12, bottom: 10),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _IconAction(
                          icon: Icons.copy_rounded,
                          tooltip: '复制',
                          onTap: hasContent ? () => _copy(context) : null,
                        ),
                        if (isLast && !failed)
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
                          _VersionSwitcher(
                            message: message,
                            controller: controller,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final text = widget.message.displayContent;
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
            style: TextStyle(
              fontSize: 14,
              height: 24 / 14,
              color: colors.textTertiary,
            ),
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
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
