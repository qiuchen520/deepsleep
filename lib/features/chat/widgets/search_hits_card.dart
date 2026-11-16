/// 联网搜索结果：折叠成一行，展开后按「标题（域名）」列出可点条目。
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
    final hits = widget.hits;
    if (hits.isEmpty && !widget.searching) return const SizedBox.shrink();
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.public_rounded, size: 14, color: colors.textTertiary),
            const SizedBox(width: 6),
            Text(
              '正在搜索…',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }
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
                  Icons.public_rounded,
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  '搜索到 ${hits.length} 个网页',
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
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final hit in hits) _SearchHitRow(hit: hit),
              ],
            ),
          ),
      ],
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
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: title,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
              ),
              TextSpan(
                text: '（$host）',
                style: TextStyle(fontSize: 13, color: colors.textTertiary),
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
