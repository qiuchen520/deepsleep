/// 深度思考折叠区。
///
/// 对齐 docs/UI_SPEC.md：标题行高 34 / 字 14/24 #61666B，面板下间距 10；
/// 展开后正文 14/24、左竖线 1px、padding 5 0 5 22，不使用背景卡片。
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
    final line = colors.textTertiary.withValues(alpha: 0.35);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: Container(
                height: 34,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _title,
                      style: TextStyle(
                        fontSize: 14,
                        height: 24 / 14,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 2),
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
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.only(bottom: 2, top: 2),
              padding: const EdgeInsets.only(left: 22, top: 5, bottom: 5),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: line, width: 1)),
              ),
              child: MarkdownView(
                data: widget.reasoning,
                selectable: false,
                compact: true,
              ),
            ),
        ],
      ),
    );
  }
}
