/// 思考面板：按时间顺序展示「思考文字 / 搜索 / 阅读网页」步骤，
/// 流式时展开，结束后自动折叠为「已思考（用时 X 秒）」。对齐官方 App。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../widgets/markdown_view.dart';
import 'favicon_cluster.dart';
import 'search_results_dialog.dart';

class ThinkingPanel extends StatefulWidget {
  const ThinkingPanel({
    super.key,
    required this.reasoning,
    required this.streaming,
    required this.startedAt,
    this.finishedAt,
    this.steps = const <ThinkingStep>[],
    this.queries = const <String>[],
    this.hits = const <SearchHit>[],
    this.visitedPages = const <SearchHit>[],
  });

  final String reasoning;
  final bool streaming;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// 有序思考链（新版记录方式）。
  final List<ThinkingStep> steps;
  final List<String> queries;
  final List<SearchHit> hits;
  final List<SearchHit> visitedPages;

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _expanded = widget.streaming;
  }

  @override
  void didUpdateWidget(covariant ThinkingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.streaming && widget.streaming) {
      setState(() => _expanded = true);
    } else if (oldWidget.streaming && !widget.streaming && _expanded) {
      setState(() => _expanded = false);
    }
  }

  String get _title {
    if (widget.streaming) return '正在思考…';
    final end = widget.finishedAt ?? widget.startedAt;
    final milliseconds = end.difference(widget.startedAt).inMilliseconds;
    final seconds = (milliseconds / 1000).ceil().clamp(1, 9999);
    return '已思考（用时 $seconds 秒）';
  }

  List<ThinkingStep> get _steps {
    if (widget.steps.isNotEmpty) return widget.steps;
    final fallback = <ThinkingStep>[];
    if (widget.reasoning.trim().isNotEmpty) {
      fallback.add(
        ThinkingStep(
          kind: ThinkingStepKind.reasoning,
          text: widget.reasoning,
        ),
      );
    }
    for (final query in widget.queries) {
      fallback.add(
        ThinkingStep(kind: ThinkingStepKind.search, queries: <String>[query]),
      );
    }
    if (widget.hits.isNotEmpty) {
      fallback.add(
        ThinkingStep(kind: ThinkingStepKind.search, hits: widget.hits),
      );
    }
    if (widget.visitedPages.isNotEmpty) {
      fallback.add(
        ThinkingStep(
          kind: ThinkingStepKind.browse,
          hits: widget.visitedPages,
        ),
      );
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final steps = _steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: SizedBox(
              height: 34,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _title,
                    style: TextStyle(
                      fontSize: 14,
                      height: 24 / 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _expanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(left: 23, bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: colors.border, width: 1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final step in steps) _buildStep(context, step),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, ThinkingStep step) {
    switch (step.kind) {
      case ThinkingStepKind.reasoning:
        return _ReasoningStep(text: step.text);
      case ThinkingStepKind.search:
        return _SearchStep(step: step, streaming: widget.streaming);
      case ThinkingStepKind.browse:
        return _BrowseStep(step: step);
    }
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({this.top = 10});

  final double top;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: top, right: 10),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: colors.textTertiary.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ReasoningStep extends StatelessWidget {
  const _ReasoningStep({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _Bullet(),
                Expanded(
                  child: MarkdownView(
                    data: paragraph,
                    selectable: false,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SearchStep extends StatelessWidget {
  const _SearchStep({required this.step, required this.streaming});

  final ThinkingStep step;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasHits = step.hits.isNotEmpty;
    final text = hasHits
        ? '搜索到 ${step.hits.length} 个网页'
        : (step.queries.isNotEmpty
            ? '搜索「${step.queries.join('、')}」'
            : '正在搜索…');
    final row = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_rounded, size: 15, color: colors.textTertiary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 24 / 14,
              color: colors.textSecondary,
            ),
          ),
          if (hasHits) ...<Widget>[
            const SizedBox(width: 8),
            FaviconCluster(hits: step.hits, max: 3, size: 16),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_right_rounded,
              size: 15,
              color: colors.textTertiary,
            ),
          ],
        ],
      ),
    );
    if (!hasHits) return row;
    return InkWell(
      onTap: () => showSearchResultsDialog(context, step.hits),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: row,
    );
  }
}

class _BrowseStep extends StatelessWidget {
  const _BrowseStep({required this.step});

  final ThinkingStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasPages = step.hits.isNotEmpty;
    final row = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.article_outlined, size: 15, color: colors.textTertiary),
          const SizedBox(width: 8),
          Text(
            hasPages ? '已浏览 ${step.hits.length} 个页面' : '正在阅读网页…',
            style: TextStyle(
              fontSize: 14,
              height: 24 / 14,
              color: colors.textSecondary,
            ),
          ),
          if (hasPages) ...<Widget>[
            const SizedBox(width: 8),
            FaviconCluster(hits: step.hits, max: 3, size: 16),
          ],
        ],
      ),
    );
    if (!hasPages) return row;
    return InkWell(
      onTap: () => showSearchResultsDialog(
        context,
        step.hits,
        title: '已浏览的页面',
      ),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: row,
    );
  }
}
