import 'package:flutter/material.dart';

import '../../../core/ui/app_avatar.dart';
import '../models/tip_round.dart';

/// Kleines Mitglieds-Profil einer Tipprunde: zeigt den ligaspezifischen
/// Teamnamen **und** den echten Nutzernamen. Den eigenen Teamnamen setzt man
/// über die Einstellungen (Zahnrad).
void showTipMemberProfile(
  BuildContext context, {
  required TipRound round,
  required RoundMember member,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _TipMemberProfileSheet(member: member),
  );
}

class _TipMemberProfileSheet extends StatelessWidget {
  const _TipMemberProfileSheet({required this.member});

  final RoundMember member;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasTeamName = member.teamName?.trim().isNotEmpty ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Row(
          children: [
            AppAvatar(
              imageUrl: member.avatarUrl,
              emoji: member.avatarEmoji,
              colorHex: member.avatarColor,
              fallbackText: member.display,
              size: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.display,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    hasTeamName ? '@${member.username}' : 'Nutzername',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
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
