/// 深度思考折叠面板：流式时显示「正在深度思考…」，结束后显示用时。
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
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: widget.streaming
                      ? CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: colors.brand,
                        )
                      : Icon(
                          Icons.check_circle_outline_rounded,
                          size: 14,
                          color: colors.success,
                        ),
                ),
                const SizedBox(width: 6),
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
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
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4, bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: colors.bgHover,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: colors.border),
            ),
            child: MarkdownView(data: widget.reasoning),
          ),
      ],
    );
  }
}
