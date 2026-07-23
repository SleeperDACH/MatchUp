import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../../core/ui/rename_league_dialog.dart';
import '../../../core/ui/team_name_dialog.dart';
import '../../auth/providers.dart';
import '../../leagues/providers.dart';
import '../../leagues/ui/visibility_settings_page.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'league_hub_screen.dart';
import 'tip_backfill_screen.dart';
import 'tip_invite_screen.dart';
import 'tip_rules_settings_screen.dart';

/// Einstellungen einer Tipprunde (über das Zahnrad). Für **alle** Mitglieder:
/// der eigene Teamname. Nur für den Ersteller: Wertung & Modi sowie Löschen.
/// Öffnet ein eigenes Vollbild-Fenster (wie die Fantasy-Einstellungen).
void showTipSettings(BuildContext context, TipRound round) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => _TipSettingsScreen(round: round)),
  );
}

class _TipSettingsScreen extends ConsumerWidget {
  const _TipSettingsScreen({required this.round});

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

    Future<void> editLogo() async {
      final messenger = ScaffoldMessenger.of(context);
      final value = await showAvatarEditor(
        context,
        storagePath: 'tip/${round.id}.jpg',
        title: 'Runden-Logo',
        circle: false,
        currentUrl: round.logoUrl,
        currentEmoji: round.logoEmoji,
        currentColor: round.logoColor,
      );
      if (value == null) return;
      try {
        await ref.read(tipRoundRepositoryProvider).setLogo(round.id,
            url: value.url, emoji: value.emoji, color: value.color);
        ref.invalidate(myRoundsProvider);
        messenger.showSnackBar(
            const SnackBar(content: Text('Runden-Logo gespeichert.')));
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

    Future<void> confirmLeave() async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tippspiel verlassen?'),
          content: Text('Du verlässt „${round.name}". Deine Tipps in dieser '
              'Liga werden entfernt. Über einen Einladungslink kannst du '
              'später wieder beitreten.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Verlassen'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref.read(tipRoundRepositoryProvider).leaveRound(round.id);
        ref.invalidate(myRoundsProvider);
        navigator.popUntil((r) => r.isFirst);
        messenger.showSnackBar(
            const SnackBar(content: Text('Tippspiel verlassen.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Verlassen fehlgeschlagen: $e')));
      }
    }

    // Wählt ein anderes Mitglied als neuen Admin (null = keins da/abgebrochen).
    Future<RoundMember?> pickNewAdmin() async {
      final others = (ref.read(roundMembersProvider(round.id)).valueOrNull ??
              const <RoundMember>[])
          .where((m) => m.userId != myId)
          .toList();
      if (others.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Kein anderes Mitglied vorhanden, dem du die '
                'Adminrechte übergeben kannst. Du kannst die Runde '
                'stattdessen löschen.')));
        return null;
      }
      return showDialog<RoundMember>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Adminrechte übergeben an …'),
          children: [
            for (final m in others)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      AppAvatar(
                        imageUrl: m.avatarUrl,
                        emoji: m.avatarEmoji,
                        colorHex: m.avatarColor,
                        fallbackText: m.username,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(m.display,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Nur Adminrechte übergeben (der bisherige Admin bleibt Mitglied).
    Future<void> confirmTransferOwnership() async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final newOwner = await pickNewAdmin();
      if (newOwner == null || !context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Adminrechte übergeben?'),
          content: Text('„${newOwner.display}" wird neuer Admin von '
              '„${round.name}". Du bleibst Mitglied, verlierst aber die '
              'Admin-Rechte.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Übergeben')),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        final repo = ref.read(tipRoundRepositoryProvider);
        await repo.transferOwnership(round.id, newOwner.userId);
        // Aktive Runde aktualisieren, damit Admin-Optionen verschwinden.
        ref.read(activeRoundProvider.notifier).state =
            await repo.fetchRound(round.id);
        ref.invalidate(myRoundsProvider);
        navigator.pop(); // Einstellungen schließen
        messenger.showSnackBar(SnackBar(
            content: Text('„${newOwner.display}" ist jetzt Admin.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Übergabe fehlgeschlagen: $e')));
      }
    }

    // Admin verlässt die Runde: erst die Adminrechte an ein anderes Mitglied
    // übergeben, dann austreten (atomar serverseitig).
    Future<void> confirmLeaveAsAdmin() async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final newOwner = await pickNewAdmin();
      if (newOwner == null || !context.mounted) return;
      // Übergabe + Austritt bestätigen.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Übergeben und verlassen?'),
          content: Text('„${newOwner.display}" wird neuer Admin von '
              '„${round.name}". Du verlässt die Runde und deine Tipps werden '
              'entfernt.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Übergeben & verlassen'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref
            .read(tipRoundRepositoryProvider)
            .transferAndLeaveRound(round.id, newOwner.userId);
        ref.invalidate(myRoundsProvider);
        navigator.popUntil((r) => r.isFirst);
        messenger.showSnackBar(const SnackBar(
            content:
                Text('Adminrechte übergeben und Tippspiel verlassen.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Verlassen fehlgeschlagen: $e')));
      }
    }

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Einstellungen')),
      body: ListView(
        children: [
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
          // Eigenständige Tipprunde: über Freunde/Chats einladen. Gekoppelte
          // Tippspiele bekommen ihre Mitglieder von der Fantasy-Liga.
          if (!round.isFantasyLinked) ...[
            const Divider(height: 1),
            ListTile(
              leading:
                  Icon(Icons.person_add_alt_1, color: scheme.primary),
              title: const Text('Mitglieder einladen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Über deine Chats & Freunde einladen'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TipInvitePlayersScreen(round: round)));
              },
            ),
          ],
          // Gekoppelte Tippspiele haben keinen eigenen Liga-Tab — die Regeln
          // sind daher hier erreichbar.
          if (round.isFantasyLinked) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.gavel_outlined, color: scheme.primary),
              title: const Text('Regeln & Punkteverteilung',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.of(context).pop();
                showTipRoundRules(context, round.scoring,
                    ref.read(selectedLeagueProvider));
              },
            ),
          ],
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
              leading: AppAvatar(
                imageUrl: round.logoUrl,
                emoji: round.logoEmoji,
                colorHex: round.logoColor,
                fallbackIcon: Icons.image_outlined,
                size: 40,
                cornerRadius: 10,
              ),
              title: const Text('Runden-Logo ändern',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Bild hochladen oder Emoji + Farbe wählen'),
              onTap: editLogo,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                  round.isPublic ? Icons.public : Icons.lock_outline,
                  color: scheme.primary),
              title: const Text('Sichtbarkeit & Beitritt',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle:
                  Text(visibilityLabel(round.visibility, round.joinPolicy)),
              trailing: RequestsBadgeChevron(
                  pending: (round.isPublic && round.isInviteOnly)
                      ? ref
                              .watch(tipJoinRequestsProvider(round.id))
                              .valueOrNull
                              ?.length ??
                          0
                      : 0),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VisibilitySettingsPage(
                          kind: 'tip',
                          id: round.id,
                          name: round.name,
                          visibility: round.visibility,
                          joinPolicy: round.joinPolicy,
                        )));
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.edit_note, color: scheme.primary),
              title: const Text('Tipps nachtragen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Für Mitglieder Tipps eintragen — auch nach Anstoß.'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TipBackfillScreen(round: round)));
              },
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
              leading: Icon(Icons.admin_panel_settings_outlined,
                  color: scheme.primary),
              title: const Text('Adminrechte übergeben',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Ein Mitglied zum neuen Admin machen; du bleibst dabei.'),
              onTap: confirmTransferOwnership,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Tippspiel verlassen',
                  style: TextStyle(
                      color: scheme.error, fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Adminrechte an ein Mitglied übergeben und austreten.'),
              onTap: confirmLeaveAsAdmin,
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
          // Mitglieder (nicht der Ersteller) können die Runde verlassen.
          if (!isCreator) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Tippspiel verlassen',
                  style: TextStyle(
                      color: scheme.error, fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Entfernt dich aus der Liga; deine Tipps werden gelöscht.'),
              onTap: confirmLeave,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
