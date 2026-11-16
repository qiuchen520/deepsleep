/// 记忆引用：正文下一行 12px 灰色小字，点击弹出记忆明细。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/memory_models.dart';
import '../../../state/conversation_controller.dart';

class MemoryCitationChip extends StatelessWidget {
  const MemoryCitationChip({
    super.key,
    required this.citedMemoryIds,
    required this.controller,
  });

  final List<String> citedMemoryIds;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (citedMemoryIds.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => _showSheet(context),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '引用 ${citedMemoryIds.length} 条记忆',
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ),
      ),
    );
  }

  Future<void> _showSheet(BuildContext context) async {
    final colors = context.colors;
    final items = controller.lastMemory.items;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.bgElevated,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.62;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '本轮引用的记忆（${citedMemoryIds.length}）',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          child: Text(
                            '本轮记忆明细已不可用（可能已被更新或删除）',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: colors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) => _MemoryRow(
                            item: items[index],
                            colors: colors,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.item, required this.colors});

  final MemoryItem item;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          item.content,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${item.kind.label} · 重要度 ${(item.importance * 100).round()}% · ${formatRelative(item.updatedAt)}',
          style: TextStyle(fontSize: 11, color: colors.textTertiary),
        ),
      ],
    );
  }
}
