/// 搜索结果弹窗：仿官方 App 的「搜索结果」面板。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../widgets/markdown_view.dart';
import '../../../widgets/soft_modal.dart';

Future<void> showSearchResultsDialog(
  BuildContext context,
  List<SearchHit> hits, {
  String title = '搜索结果',
}) async {
  final colors = context.colors;
  final screenHeight = MediaQuery.sizeOf(context).height;
  // 给弹窗的标题/按钮/内边距留出空间，避免小屏溢出。
  final maxHeight = (screenHeight - 320).clamp(160.0, 520.0).toDouble();
  await showSoftDialog<void>(
    context: context,
    title: title,
    maxWidth: 640,
    child: SizedBox(
      height: maxHeight,
      child: hits.isEmpty
          ? Center(
              child: Text(
                '暂无搜索结果',
                style: TextStyle(fontSize: 13, color: colors.textTertiary),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: hits.length,
              separatorBuilder: (_, __) => Divider(
                height: 24,
                color: colors.border,
              ),
              itemBuilder: (context, index) => _SearchResultItem(
                hit: hits[index],
                index: index + 1,
              ),
            ),
    ),
  );
}

class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({required this.hit, required this.index});

  final SearchHit hit;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = Uri.tryParse(hit.url);
    final host = (uri != null && uri.host.isNotEmpty) ? uri.host : hit.url;
    final title = hit.title.trim().isEmpty ? host : hit.title;
    return InkWell(
      onTap: () => openExternalUrl(context, hit.url),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _HostIcon(host: host),
                const SizedBox(width: 6),
                Text(
                  host,
                  style: TextStyle(
                    fontSize: 12,
                    height: 18 / 12,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                height: 22 / 15,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            if (hit.snippet.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                hit.snippet.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 20 / 13,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HostIcon extends StatelessWidget {
  const _HostIcon({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final letter = host.isEmpty ? '?' : host.characters.first.toUpperCase();
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.brand.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: colors.brand,
          height: 1,
        ),
      ),
    );
  }
}
