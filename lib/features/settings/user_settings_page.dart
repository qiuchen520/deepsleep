/// 用户设置：用户档案的切换、新增、编辑与删除。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/profile_models.dart';
import '../../state/app_services.dart';
import '../../widgets/soft_modal.dart';
import 'settings_shared.dart';

class UserSettingsPage extends StatelessWidget {
  const UserSettingsPage({super.key, required this.services});

  final AppServices services;

  Future<void> _switch(BuildContext context, UserProfile profile) async {
    if (services.settings.settings.activeProfileId == profile.id) return;
    final messenger = ScaffoldMessenger.of(context);
    await services.settings.switchProfile(profile.id);
    await services.conversations.reloadForProfile();
    await services.memories.refresh();
    messenger.showSnackBar(
      SnackBar(content: Text('已切换到「${profile.name}」')),
    );
  }

  Future<void> _edit(BuildContext context, UserProfile? profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = await showProfileEditor(context, profile: profile);
    if (draft == null) return;
    if (profile == null) {
      final created = await services.settings.createProfile(
        name: draft.name,
        emoji: draft.emoji,
        persona: draft.persona,
      );
      await services.settings.switchProfile(created.id);
      await services.conversations.reloadForProfile();
      await services.memories.refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('已新增并切换到新档案')),
      );
    } else {
      await services.settings.updateProfile(
        profile.copyWith(
          name: draft.name,
          emoji: draft.emoji,
          persona: draft.persona,
        ),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('用户档案已更新')),
      );
    }
  }

  Future<void> _delete(BuildContext context, UserProfile profile) async {
    if (services.settings.profiles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个用户档案')),
      );
      return;
    }
    final confirmed = await showSoftConfirm(
      context: context,
      title: '删除用户档案',
      description: '删除后该档案不再出现在切换列表中，其对话与记忆仍保留在本地数据库。'
          '\n\n确定删除「${profile.name}」吗？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    final wasActive =
        services.settings.settings.activeProfileId == profile.id;
    await services.settings.deleteProfile(profile.id);
    if (wasActive) {
      await services.conversations.reloadForProfile();
      await services.memories.refresh();
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('用户档案已删除')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final controller = services.settings;
        final profiles = controller.profiles;
        final activeId = controller.settings.activeProfileId;

        return SettingsScaffold(
          title: '用户',
          children: <Widget>[
            SettingsSection(
              title: '用户档案',
              footnote: '每个档案拥有独立的对话与长期记忆。',
              rows: <Widget>[
                for (final profile in profiles)
                  _ProfileRow(
                    profile: profile,
                    active: profile.id == activeId,
                    onTap: () => _switch(context, profile),
                    onEdit: () => _edit(context, profile),
                    onDelete: () => _delete(context, profile),
                  ),
              ],
            ),
            SettingsSection(
              title: '管理',
              rows: <Widget>[
                SettingsActionRow(
                  label: '新增用户档案',
                  onTap: () => _edit(context, null),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.active,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final UserProfile profile;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  profile.emoji,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w400,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (active)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '当前',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.brandText,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (profile.persona.trim().isNotEmpty)
                      Text(
                        profile.persona.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑档案',
                onPressed: onEdit,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.edit_outlined,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                tooltip: '删除档案',
                onPressed: onDelete,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
