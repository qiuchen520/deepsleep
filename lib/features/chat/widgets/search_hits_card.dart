/// 联网搜索来源胶囊：显示「N 个网页」+ favicon；点击打开搜索结果弹窗。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import 'favicon_cluster.dart';
import 'search_results_dialog.dart';

class SearchHitsCard extends StatelessWidget {
  const SearchHitsCard({
    super.key,
    required this.hits,
    this.searching = false,
    this.compact = false,
  });

  final List<SearchHit> hits;

  /// 正在检索（还没有结果）时展示「正在搜索…」。
  final bool searching;

  /// 紧凑模式：只显示「N 个网页」小胶囊（回答末尾的来源汇总）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = context.isDark ? colors.border : colors.borderStrong;
    if (hits.isEmpty && !searching) return const SizedBox.shrink();
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
      child: InkWell(
        onTap: () => showSearchResultsDialog(context, hits),
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (compact)
                FaviconCluster(hits: hits, max: 3, size: 18)
              else
                Icon(
                  Icons.public_rounded,
                  size: 16,
                  color: colors.textSecondary,
                ),
              const SizedBox(width: 7),
              Text(
                compact ? '${hits.length} 个网页' : '搜索到 ${hits.length} 个网页',
                style: TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
