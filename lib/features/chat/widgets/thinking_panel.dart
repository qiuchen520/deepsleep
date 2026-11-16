/// 深度思考折叠行：流式时「正在深度思考…」，结束后显示用时；
/// 展开后是左侧 2px 淡边框的灰字，不做背景卡片。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/markdown_view.dart';

class ThinkingPanel extends StatefulWidget {
  const ThinkingPanel({
    super.key,
    required this.reasoning,
    required this.streaming,
    required this.startedAt,
    this.finishedAt,
  });

  final String reasoning;
  final bool streaming;
  final DateTime startedAt;
  final DateTime? finishedAt;

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  bool _expanded = false;

  String get _title {
    if (widget.streaming) return '正在深度思考…';
    final end = widget.finishedAt ?? widget.startedAt;
    final milliseconds = end.difference(widget.startedAt).inMilliseconds;
    final seconds = (milliseconds / 1000).ceil().clamp(1, 9999);
    return '已深度思考（用时 $seconds 秒）';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.reasoning.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  _title,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.border, width: 2),
              ),
            ),
            child: MarkdownView(
              data: widget.reasoning,
              selectable: false,
              compact: true,
            ),
          ),
      ],
    );
  }
}
