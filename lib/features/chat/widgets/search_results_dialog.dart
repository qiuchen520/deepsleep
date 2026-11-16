/// 搜索结果弹窗：仿官方 App 的「搜索结果」面板。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../widgets/markdown_view.dart';
import 'favicon_cluster.dart';

Future<void> showSearchResultsDialog(
  BuildContext context,
  List<SearchHit> hits, {
  String title = '搜索结果',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.36),
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return Dialog(
        backgroundColor: colors.bgElevated,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
                child: Row(
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FaviconCluster(hits: hits, max: 3, size: 16),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  itemCount: hits.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 24,
                    color: colors.border,
                  ),
                  itemBuilder: (context, index) {
                    final hit = hits[index];
                    return _SearchResultItem(hit: hit, index: index + 1);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
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
