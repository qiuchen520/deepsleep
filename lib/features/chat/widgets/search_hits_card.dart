/// 联网搜索来源汇总按钮与展开列表。
///
/// 对齐 docs/UI_SPEC.md：margin-top 16、padding 4 10 4 4、圆角 100、边框 l2、
/// 字 14/24；展开后列出「标题（域名）」可点。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../widgets/markdown_view.dart';

class SearchHitsCard extends StatefulWidget {
  const SearchHitsCard({
    super.key,
    required this.hits,
    this.searching = false,
  });

  final List<SearchHit> hits;

  /// 正在检索（还没有结果）时展示「正在搜索…」。
  final bool searching;

  @override
  State<SearchHitsCard> createState() => _SearchHitsCardState();
}

class _SearchHitsCardState extends State<SearchHitsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = context.isDark ? colors.border : colors.borderStrong;
    final hits = widget.hits;
    if (hits.isEmpty && !widget.searching) return const SizedBox.shrink();
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.public_rounded, size: 16, color: colors.textTertiary),
            const SizedBox(width: 6),
            Text(
              '正在搜索…',
              style: TextStyle(
                fontSize: 14,
                height: 24 / 14,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(100),
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.public_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '搜索到 ${hits.length} 个网页',
                    style: TextStyle(
                      fontSize: 14,
                      height: 24 / 14,
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
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final hit in hits) _SearchHitRow(hit: hit),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchHitRow extends StatelessWidget {
  const _SearchHitRow({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = Uri.tryParse(hit.url);
    final host = (uri != null && uri.host.isNotEmpty) ? uri.host : hit.url;
    final title = hit.title.trim().isEmpty ? host : hit.title;
    return InkWell(
      onTap: () => openExternalUrl(context, hit.url),
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: title,
                style: TextStyle(
                  fontSize: 14,
                  height: 24 / 14,
                  color: colors.textPrimary,
                ),
              ),
              TextSpan(
                text: '（$host）',
                style: TextStyle(
                  fontSize: 14,
                  height: 24 / 14,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
