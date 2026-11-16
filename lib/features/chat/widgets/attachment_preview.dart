/// 附件 chip：输入区待发附件（可删除）与消息里的附件展示。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';

/// 人类可读的文件体积。
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData attachmentIcon(AttachmentKind kind) {
  switch (kind) {
    case AttachmentKind.image:
      return Icons.image_outlined;
    case AttachmentKind.text:
      return Icons.description_outlined;
    case AttachmentKind.document:
      return Icons.insert_drive_file_outlined;
  }
}

class AttachmentChip extends StatelessWidget {
  const AttachmentChip({super.key, required this.attachment, this.onRemove});

  final AttachmentRef attachment;

  /// 传入时展示删除按钮（输入区待发附件用）。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final remove = onRemove;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: EdgeInsets.fromLTRB(8, 4, remove == null ? 8.0 : 4.0, 4),
      decoration: BoxDecoration(
        color: colors.bgHover,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            attachmentIcon(attachment.kind),
            size: 14,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                Text(
                  formatFileSize(attachment.size),
                  style: TextStyle(fontSize: 10, color: colors.textTertiary),
                ),
              ],
            ),
          ),
          if (remove != null)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: InkWell(
                onTap: remove,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
