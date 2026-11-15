/// 记忆引用 chip：展示本轮助手回复引用了多少条记忆，点击查看明细。
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
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colors.brandSoft,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: colors.brand.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.psychology_alt,
                size: 13,
                color: colors.brandText,
              ),
              const SizedBox(width: 4),
              Text(
                '引用 ${citedMemoryIds.length} 条记忆',
                style: TextStyle(fontSize: 11.5, color: colors.brandText),
              ),
            ],
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
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.psychology_alt,
                        size: 18,
                        color: colors.brandText,
                      ),
                      const SizedBox(width: 6),
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) => _MemoryItemTile(
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

class _MemoryItemTile extends StatelessWidget {
  const _MemoryItemTile({required this.item, required this.colors});

  final MemoryItem item;
  final AppColors colors;

  Color get _kindColor {
    switch (item.kind) {
      case MemoryKind.fact:
        return colors.brand;
      case MemoryKind.preference:
        return colors.success;
      case MemoryKind.profile:
        return colors.warning;
      case MemoryKind.event:
        return colors.brandText;
      case MemoryKind.task:
        return colors.danger;
      case MemoryKind.relation:
        return colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kindColor = _kindColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.bgBase,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: kindColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  item.kind.label,
                  style: TextStyle(fontSize: 10, color: kindColor),
                ),
              ),
              const Spacer(),
              Text(
                '重要度 ${(item.importance * 100).round()}%',
                style: TextStyle(fontSize: 10.5, color: colors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.content,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatRelative(item.updatedAt),
            style: TextStyle(fontSize: 10.5, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
