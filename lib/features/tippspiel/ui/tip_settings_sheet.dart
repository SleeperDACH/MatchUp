import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/ui/form_section.dart';
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
    MaterialPageRoute(builder: (_) => _TipSettingsScreen(startRound: round)),
  );
}

class _TipSettingsScreen extends ConsumerWidget {
  const _TipSettingsScreen({required this.startRound});

  /// Stand beim Öffnen. Maßgeblich ist unten der **frische** Stand aus
  /// `myRoundsProvider`: kommt man von einer Unterseite zurück (umbenannt,
  /// Logo oder Sichtbarkeit geändert), muss hier der neue Wert stehen.
  /// Vorher schloss sich der Screen beim Öffnen einer Unterseite — genau
  /// deshalb, und das kostete den natürlichen Zurück-Weg.
  final TipRound startRound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final round = ref
            .watch(myRoundsProvider)
            .valueOrNull
            ?.where((r) => r.id == startRound.id)
            .firstOrNull ??
        startRound;
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

    // Gruppen statt einer durchlaufenden Liste: vorher standen zwölf gleich
    // aussehende Zeilen untereinander — Teamname, Logo, Nachtragen, Löschen —
    // alle fett, alle mit demselben grünen Symbol. Zusammengehörendes steht
    // jetzt beieinander, und Zerstörerisches ganz unten und abgesetzt.
    final mitglieder = <Widget>[
      // Eigenständige Tipprunde: über Freunde/Chats einladen. Gekoppelte
      // Tippspiele bekommen ihre Mitglieder von der Fantasy-Liga.
      if (!round.isFantasyLinked)
        _Zeile(
          icon: Icons.person_add_alt_1,
          titel: 'Mitglieder einladen',
          untertitel: 'Über deine Chats & Freunde',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TipInvitePlayersScreen(round: round),
            ),
          ),
        ),
      if (isCreator)
        _Zeile(
          icon: round.isPublic ? Icons.public : Icons.lock_outline,
          titel: 'Sichtbarkeit & Beitritt',
          untertitel: visibilityLabel(round.visibility, round.joinPolicy),
          trailing: RequestsBadgeChevron(
            pending: (round.isPublic && round.isInviteOnly)
                ? ref
                          .watch(tipJoinRequestsProvider(round.id))
                          .valueOrNull
                          ?.length ??
                      0
                : 0,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VisibilitySettingsPage(
                kind: 'tip',
                id: round.id,
                name: round.name,
                visibility: round.visibility,
                joinPolicy: round.joinPolicy,
              ),
            ),
          ),
        ),
      if (isCreator)
        _Zeile(
          icon: Icons.admin_panel_settings_outlined,
          titel: 'Adminrechte übergeben',
          untertitel: 'Ein Mitglied zum Admin machen; du bleibst dabei',
          onTap: confirmTransferOwnership,
        ),
    ];

    final wertung = <Widget>[
      if (isCreator)
        _Zeile(
          icon: Icons.tune,
          titel: 'Wertung & Modi',
          untertitel: 'Punkte, Quoten-Bonus, Head-to-Head, Bonustipps …',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TipRulesSettingsScreen(round: round),
            ),
          ),
        ),
      // Gekoppelte Tippspiele haben keinen eigenen Liga-Tab — die Regeln
      // sind daher nur hier erreichbar.
      if (round.isFantasyLinked)
        _Zeile(
          icon: Icons.gavel_outlined,
          titel: 'Regeln & Punkteverteilung',
          untertitel: 'Wie in dieser Runde gewertet wird',
          onTap: () => showTipRoundRules(
            context,
            round.scoring,
            ref.read(selectedLeagueProvider),
          ),
        ),
      if (isCreator)
        _Zeile(
          icon: Icons.edit_note,
          titel: 'Tipps nachtragen',
          untertitel: 'Für Mitglieder eintragen — auch nach Anstoß',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TipBackfillScreen(round: round)),
          ),
        ),
    ];

    final erscheinung = <Widget>[
      if (isCreator)
        _Zeile(
          icon: Icons.drive_file_rename_outline,
          titel: 'Name ändern',
          untertitel: round.name,
          onTap: renameRound,
        ),
      if (isCreator)
        _Zeile(
          leading: AppAvatar(
            imageUrl: round.logoUrl,
            emoji: round.logoEmoji,
            colorHex: round.logoColor,
            fallbackIcon: Icons.image_outlined,
            size: 30,
            cornerRadius: 8,
          ),
          titel: 'Logo ändern',
          untertitel: 'Bild hochladen oder Emoji + Farbe wählen',
          onTap: editLogo,
        ),
    ];

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          _Kopf(round: round),
          const SizedBox(height: 18),
          FormSection.zeilen(
            titel: 'Meine Teilnahme',
            kinder: [
              _Zeile(
                icon: Icons.badge_outlined,
                titel: 'Mein Teamname',
                untertitel: (myName?.teamName?.trim().isNotEmpty ?? false)
                    ? myName!.teamName!.trim()
                    : 'Wird in dieser Liga statt deines Nutzernamens gezeigt',
                onTap: editTeamName,
              ),
            ],
          ),
          FormSection.zeilen(titel: 'Mitglieder', kinder: mitglieder),
          FormSection.zeilen(titel: 'Regeln & Wertung', kinder: wertung),
          FormSection.zeilen(titel: 'Erscheinungsbild', kinder: erscheinung),
          FormSection.zeilen(
            titel: 'Gefahrenzone',
            gefahr: true,
            kinder: [
              _Zeile(
                icon: Icons.logout,
                titel: 'Tippspiel verlassen',
                untertitel: isCreator
                    ? 'Adminrechte an ein Mitglied übergeben und austreten'
                    : 'Entfernt dich aus der Liga; deine Tipps werden gelöscht',
                gefahr: true,
                onTap: isCreator ? confirmLeaveAsAdmin : confirmLeave,
              ),
              if (isCreator)
                _Zeile(
                  icon: Icons.delete_outline,
                  titel: 'Tippspiel löschen',
                  untertitel: 'Mit allen Tipps und dem Chat, endgültig',
                  gefahr: true,
                  onTap: confirmDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kopf des Einstellungs-Screens: zeigt, worum es überhaupt geht. Ohne ihn
/// stand über zwölf Zeilen nur „Einstellungen" — bei mehreren Tipprunden zu
/// wenig, um sicher zu sein, welche man gerade ändert.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final league = Leagues.byId(round.leagueId);
    final extra = round.competitions.length - 1;
    return Row(
      children: [
        AppAvatar(
          imageUrl: round.logoUrl,
          emoji: round.logoEmoji,
          colorHex: round.logoColor,
          fallbackIcon: Icons.emoji_events_outlined,
          size: 44,
          cornerRadius: 12,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                round.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                extra > 0 ? '${league.name} +$extra' : league.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Eine Einstellungszeile. Der Titel ist bewusst **nicht** fett: vorher
/// schrie jede der zwölf Zeilen gleich laut, und die Überschrift der Gruppe
/// trägt die Gliederung.
class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.titel,
    required this.untertitel,
    required this.onTap,
    this.icon,
    this.leading,
    this.trailing,
    this.gefahr = false,
  });

  final String titel;
  final String untertitel;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final bool gefahr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farbe = gefahr ? scheme.error : scheme.onSurface;
    return ListTile(
      leading:
          leading ??
          Icon(
            icon,
            color: gefahr
                ? scheme.error
                : scheme.onSurfaceVariant.withValues(alpha: 0.9),
          ),
      title: Text(
        titel,
        style: TextStyle(fontWeight: FontWeight.w600, color: farbe),
      ),
      subtitle: Text(
        untertitel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
      ),
      trailing:
          trailing ??
          Icon(
            Icons.chevron_right,
            size: 20,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
      onTap: onTap,
    );
  }
}
