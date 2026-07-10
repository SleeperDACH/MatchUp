import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/team_name_dialog.dart';
import '../../auth/providers.dart';
import '../models/tip_round.dart';
import '../providers.dart';

/// Kleines Mitglieds-Profil einer Tipprunde: zeigt den ligaspezifischen
/// Teamnamen **und** den echten Nutzernamen. Ist es der eigene Eintrag, lässt
/// sich der Teamname hier setzen.
void showTipMemberProfile(
  BuildContext context, {
  required TipRound round,
  required RoundMember member,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _TipMemberProfileSheet(round: round, member: member),
  );
}

class _TipMemberProfileSheet extends ConsumerWidget {
  const _TipMemberProfileSheet({required this.round, required this.member});

  final TipRound round;
  final RoundMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final isMe = member.userId == myId;
    // Frische Daten (Teamname kann sich geändert haben).
    final live = (ref.watch(roundMembersProvider(round.id)).valueOrNull ??
            const <RoundMember>[])
        .where((m) => m.userId == member.userId)
        .firstOrNull ??
        member;
    final hasTeamName = live.teamName?.trim().isNotEmpty ?? false;

    Future<void> editName() async {
      final name = await showTeamNameDialog(context, current: live.teamName);
      if (name == null) return;
      await ref.read(tipRoundRepositoryProvider).setTeamName(round.id, name);
      ref.invalidate(roundMembersProvider(round.id));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  child: Text(
                      (live.display.isEmpty ? '?' : live.display[0])
                          .toUpperCase(),
                      style: TextStyle(color: scheme.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(live.display,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        hasTeamName ? '@${live.username}' : 'Nutzername',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isMe) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.badge_outlined),
                label: Text(hasTeamName
                    ? 'Teamname ändern'
                    : 'Teamnamen für diese Liga setzen'),
                onPressed: editName,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
