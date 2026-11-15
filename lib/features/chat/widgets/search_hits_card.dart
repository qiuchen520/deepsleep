/// 联网搜索结果卡片：可折叠，点击条目用浏览器打开来源。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../widgets/markdown_view.dart';

class SearchHitsCard extends StatefulWidget {
  const SearchHitsCard({super.key, required this.hits});

  final List<SearchHit> hits;

  @override
  State<SearchHitsCard> createState() => _SearchHitsCardState();
}

class _SearchHitsCardState extends State<SearchHitsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hits = widget.hits;
    if (hits.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 16,
                    color: colors.brandText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '搜索到 ${hits.length} 个网页',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (var i = 0; i < hits.length; i++)
              _SearchHitTile(index: i, hit: hits[i]),
        ],
      ),
    );
  }
}

class _SearchHitTile extends StatelessWidget {
  const _SearchHitTile({required this.index, required this.hit});

  final int index;
  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = Uri.tryParse(hit.url);
    final host = (uri != null && uri.host.isNotEmpty) ? uri.host : hit.url;
    return InkWell(
      onTap: () => openExternalUrl(context, hit.url),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 18,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '${index + 1}.',
                  style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hit.title.trim().isEmpty ? host : hit.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (hit.snippet.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      hit.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
