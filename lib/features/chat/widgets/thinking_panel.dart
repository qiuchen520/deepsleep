/// 思考面板：流式时展开显示思考过程与搜索/阅读步骤，结束后自动折叠成一行
/// 「已思考（用时 X 秒）」。结构对齐官方 App。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../widgets/markdown_view.dart';
import 'favicon_cluster.dart';

class ThinkingPanel extends StatefulWidget {
  const ThinkingPanel({
    super.key,
    required this.reasoning,
    required this.streaming,
    required this.startedAt,
    this.finishedAt,
    this.queries = const <String>[],
    this.hits = const <SearchHit>[],
    this.visitedPages = const <SearchHit>[],
  });

  final String reasoning;
  final bool streaming;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// 搜索用过的查询词。
  final List<String> queries;

  /// 搜索结果。
  final List<SearchHit> hits;

  /// 已阅读的网页。
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
    // 开始生成时展开，结束后自动折叠（对齐官方 App 的行为）。
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

  bool get _hasSteps =>
      widget.reasoning.trim().isNotEmpty ||
      widget.queries.isNotEmpty ||
      widget.hits.isNotEmpty ||
      widget.visitedPages.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (!_hasSteps) return const SizedBox.shrink();
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
                    left: BorderSide(
                      color: colors.border,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (widget.reasoning.trim().isNotEmpty)
                      MarkdownView(
                        data: widget.reasoning,
                        selectable: false,
                        compact: true,
                      ),
                    for (final query in widget.queries)
                      _StepRow(
                        icon: Icons.search_rounded,
                        text: '搜索「${query.trim()}」',
                        hits: const <SearchHit>[],
                      ),
                    if (widget.hits.isNotEmpty)
                      _StepRow(
                        icon: Icons.search_rounded,
                        text: '搜索到 ${widget.hits.length} 个网页',
                        hits: widget.hits,
                      ),
                    if (widget.visitedPages.isNotEmpty)
                      _StepRow(
                        icon: Icons.article_outlined,
                        text: '已浏览 ${widget.visitedPages.length} 个页面',
                        hits: widget.visitedPages,
                      ),
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
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.text,
    required this.hits,
  });

  final IconData icon;
  final String text;
  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colors.textTertiary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 24 / 14,
              color: colors.textSecondary,
            ),
          ),
          if (hits.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            FaviconCluster(hits: hits, max: 3, size: 16),
          ],
        ],
      ),
    );
  }
}
