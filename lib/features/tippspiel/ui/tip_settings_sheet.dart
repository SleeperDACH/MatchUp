import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/rename_league_dialog.dart';
import '../../../core/ui/team_name_dialog.dart';
import '../../auth/providers.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'tip_rules_settings_screen.dart';

/// Einstellungen einer Tipprunde (über das Zahnrad). Für **alle** Mitglieder:
/// der eigene Teamname. Nur für den Ersteller: Wertung & Modi sowie Löschen.
void showTipSettings(BuildContext context, TipRound round) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _TipSettingsSheet(round: round),
  );
}

class _TipSettingsSheet extends ConsumerWidget {
  const _TipSettingsSheet({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final isCreator = myId == round.createdBy;
    final myName = (ref.watch(roundMembersProvider(round.id)).valueOrNull ??
            const <RoundMember>[])
        .where((m) => m.userId == myId)
        .firstOrNull;

    Future<void> editTeamName() async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final name =
          await showTeamNameDialog(context, current: myName?.teamName);
      if (name == null) return;
      try {
        await ref.read(tipRoundRepositoryProvider).setTeamName(round.id, name);
        ref.invalidate(roundMembersProvider(round.id));
        navigator.pop();
        messenger
            .showSnackBar(const SnackBar(content: Text('Teamname gespeichert.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }

    Future<void> renameRound() async {
      final messenger = ScaffoldMessenger.of(context);
      final newName = await showRenameLeagueDialog(context, current: round.name);
      if (newName == null || newName == round.name) return;
      try {
        await ref.read(tipRoundRepositoryProvider).renameRound(round.id, newName);
        ref.invalidate(myRoundsProvider);
        messenger.showSnackBar(
            const SnackBar(content: Text('Liga-Name geändert.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }

    Future<void> confirmDelete() async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tippspiel löschen?'),
          content: Text('„${round.name}" wird mit allen Tipps und dem Chat '
              'endgültig gelöscht. Das kann nicht rückgängig gemacht werden.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref.read(tipRoundRepositoryProvider).deleteRound(round.id);
        ref.invalidate(myRoundsProvider);
        navigator.popUntil((r) => r.isFirst);
        messenger
            .showSnackBar(const SnackBar(content: Text('Tippspiel gelöscht.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
      }
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Einstellungen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          ListTile(
            leading: Icon(Icons.badge_outlined, color: scheme.primary),
            title: const Text('Mein Teamname',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              (myName?.teamName?.trim().isNotEmpty ?? false)
                  ? myName!.teamName!.trim()
                  : 'Wird in dieser Liga statt deines Nutzernamens gezeigt.',
            ),
            onTap: editTeamName,
          ),
          if (isCreator) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline,
                  color: scheme.primary),
              title: const Text('Liga-Name ändern',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(round.name),
              onTap: renameRound,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.tune, color: scheme.primary),
              title: const Text('Wertung & Modi bearbeiten',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Punkte, Quoten-Bonus, Head-to-Head, Bonustipps …'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TipRulesSettingsScreen(round: round)));
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Tippspiel löschen',
                  style: TextStyle(
                      color: scheme.error, fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Entfernt die Tipprunde mit allen Tipps und dem Chat.'),
              onTap: confirmDelete,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
