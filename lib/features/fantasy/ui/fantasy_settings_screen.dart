import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/pill_selector.dart';
import '../../../core/ui/app_avatar.dart';
import '../../../core/ui/rename_league_dialog.dart';
import '../../../core/ui/team_name_dialog.dart';
import '../../auth/providers.dart';
import '../../leagues/providers.dart';
import '../../leagues/ui/visibility_settings_page.dart';
import '../../tippspiel/providers.dart';
import 'kader_limits_editor.dart';
import 'wert_stepper.dart';
import '../logic/playoff.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'draft_board_screen.dart';
import 'fantasy_admin_screen.dart';
import 'scoring_info_screen.dart';

/// Einstellungen einer Fantasy-Liga als Menü: je Bereich eine eigene Seite.
class FantasyLeagueSettingsScreen extends ConsumerWidget {
  const FantasyLeagueSettingsScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Live-Stand, damit die Zusammenfassungen nach dem Speichern stimmen.
    final l = ref.watch(draftLeagueProvider(league.id)).valueOrNull ?? league;
    final myId = ref.watch(currentUserProvider)?.id;
    final isOwner = myId == l.createdBy;
    final managerList = ref.watch(fantasyManagersProvider(l.id)).valueOrNull;
    final myManager =
        managerList?.where((m) => m.userId == myId).firstOrNull;

    void open(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));

    Future<void> editTeamName() async {
      final messenger = ScaffoldMessenger.of(context);
      final name =
          await showTeamNameDialog(context, current: myManager?.teamName);
      if (name == null) return;
      try {
        await ref.read(fantasyLeagueRepositoryProvider).setTeamName(l.id, name);
        ref.invalidate(fantasyManagersProvider(l.id));
        messenger.showSnackBar(
            const SnackBar(content: Text('Teamname gespeichert.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }

    Future<void> renameLeague() async {
      final messenger = ScaffoldMessenger.of(context);
      final newName = await showRenameLeagueDialog(context, current: l.name);
      if (newName == null || newName == l.name) return;
      try {
        await ref.read(fantasyLeagueRepositoryProvider).renameLeague(l.id, newName);
        ref.invalidate(draftLeagueProvider(l.id));
        ref.invalidate(myFantasyLeaguesProvider);
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
        storagePath: 'fantasy/${l.id}.jpg',
        title: 'Liga-Logo',
        circle: false,
        currentUrl: l.logoUrl,
        currentEmoji: l.logoEmoji,
        currentColor: l.logoColor,
      );
      if (value == null) return;
      try {
        await ref.read(fantasyLeagueRepositoryProvider).setLogo(l.id,
            url: value.url, emoji: value.emoji, color: value.color);
        ref.invalidate(draftLeagueProvider(l.id));
        ref.invalidate(myFantasyLeaguesProvider);
        messenger.showSnackBar(
            const SnackBar(content: Text('Liga-Logo gespeichert.')));
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            const Text('Einstellungen'),
            Text(l.name,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.primary)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // Liga-Identität (nur Ersteller).
          if (isOwner) ...[
            _Section('Liga', farbe: _grpLiga),
            _settingsGroup(context, [
              ListTile(
                leading: Icon(Icons.drive_file_rename_outline),
                title: const Text('Liga-Name ändern'),
                subtitle: Text(l.name),
                trailing: const _Chevron(),
                onTap: renameLeague,
              ),
              ListTile(
                leading: Icon(Icons.image_outlined),
                title: const Text('Liga-Logo ändern'),
                subtitle: const Text('Bild hochladen oder Emoji + Farbe wählen'),
                trailing: const _Chevron(),
                onTap: editLogo,
              ),
              ListTile(
                leading: Icon(l.isPublic ? Icons.public : Icons.lock_outline),
                title: const Text('Sichtbarkeit & Beitritt'),
                subtitle: Text(visibilityLabel(l.visibility, l.joinPolicy)),
                trailing: RequestsBadgeChevron(
                    pending: (l.isPublic && l.isInviteOnly)
                        ? ref
                                .watch(fantasyJoinRequestsProvider(l.id))
                                .valueOrNull
                                ?.length ??
                            0
                        : 0),
                onTap: () => open(VisibilitySettingsPage(
                      kind: 'fantasy',
                      id: l.id,
                      name: l.name,
                      visibility: l.visibility,
                      joinPolicy: l.joinPolicy,
                    )),
              ),
            ], farbe: _grpLiga),
          ],

          // Der Draft — für alle, nicht nur den Ersteller. Nach dem letzten
          // Pick verschwindet der Draft-Raum aus der Liga-Übersicht
          // (`if (!draftFullyDone)`), und damit war das Board nicht mehr
          // erreichbar. Hier kommt man wieder heran.
          if (l.draftStatus != DraftStatus.setup) ...[
            _Section('Draft', farbe: _grpAdmin),
            _settingsGroup(context, [
              ListTile(
                leading: const Icon(Icons.grid_on_outlined),
                title: const Text('Draft-Board'),
                subtitle: Text(l.draftStatus == DraftStatus.done
                    ? 'Nachschauen, wer wen gezogen hat'
                    : 'Der Draft läuft gerade'),
                trailing: const _Chevron(),
                onTap: () => open(DraftBoardScreen(league: l)),
              ),
            ], farbe: _grpAdmin),
          ],

          // Persönliches.
          _Section('Mein Team', farbe: _grpTeam),
          _settingsGroup(context, [
            ListTile(
              leading: Icon(Icons.badge_outlined),
              title: const Text('Mein Teamname'),
              subtitle: Text(
                (myManager?.teamName?.trim().isNotEmpty ?? false)
                    ? myManager!.teamName!.trim()
                    : 'In dieser Liga statt deines Nutzernamens',
              ),
              trailing: const _Chevron(),
              onTap: editTeamName,
            ),
          ], farbe: _grpTeam),

          // Spielregeln & Format.
          _Section('Regeln & Format', farbe: _grpRegeln),
          _settingsGroup(context, [
            ListTile(
              leading: Icon(Icons.calculate_outlined),
              title: const Text('Punktevergabe'),
              subtitle: const Text('Wie Fantasy-Punkte vergeben werden'),
              trailing: const _Chevron(),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ScoringInfoScreen())),
            ),
            // Die Teilnehmerzahl. Die Seite dahinter gab es schon, sie war nur
            // von nirgendwo zu erreichen — `LeagueSettingsPage` wurde in
            // keiner Datei geöffnet. Wer die Zahl nach dem Anlegen ändern
            // wollte, fand im Zahnrad Draft, Playoffs, Punkte und
            // Sichtbarkeit, aber nichts für die Liga-Größe.
            ListTile(
              leading: Icon(Icons.groups),
              title: const Text('Teilnehmerzahl'),
              subtitle: Text(l.maxTeams != null
                  ? 'Höchstens ${l.maxTeams} Teams'
                  : 'Ohne eigenes Limit — höchstens 18'),
              trailing: const _Chevron(),
              onTap: () => open(LeagueSettingsPage(league: l)),
            ),
            ListTile(
              leading: Icon(Icons.sports),
              title: const Text('Draft-Einstellungen'),
              subtitle: Text(
                  '${l.pickTime.label} · ${l.rounds} Runden${l.hasPause ? ' · Pause' : ''}'),
              trailing: const _Chevron(),
              onTap: () => open(DraftSettingsPage(league: l)),
            ),
            // Kader-Limits je Position. Nur der Ersteller darf sie ändern
            // (das erzwingt die RLS ohnehin); anzeigen tun wir sie allen,
            // damit jeder die Regel kennt, nach der er draftet.
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Kader-Limits'),
              subtitle: Text(_kaderLimitText(l.roster)),
              trailing: const _Chevron(),
              onTap: () => open(KaderLimitsPage(league: l)),
            ),
            ListTile(
              leading: Icon(Icons.emoji_events_outlined),
              title: const Text('Playoff-Einstellungen'),
              subtitle: Text(l.hasPlayoffs
                  ? '${l.playoffTeams} Teams · ${l.playoffWeeks == 2 ? '2-Wochen' : '1-Wochen'}-Partien'
                  : 'noch nicht konfiguriert'),
              trailing: const _Chevron(),
              onTap: () => open(PlayoffSettingsPage(league: l)),
            ),
          ], farbe: _grpRegeln),

          // Rollover in die nächste Saison: sobald die laufende Saison steht
          // (Draft fertig). Danach steht der U20-Draft im Setup an.
          if (l.mode == FantasyMode.dynasty &&
              isOwner &&
              l.draftStatus == DraftStatus.done) ...[
            _Section('Neue Saison', farbe: _grpAdmin),
            _settingsGroup(context, [
              ListTile(
                leading: Icon(Icons.calendar_month),
                title: const Text('Saison-Rollover'),
                subtitle: Text(
                    'Startet Saison ${l.season + 1}/${(l.season + 2) % 100}: '
                    'Kader bleibt, danach ein neuer U20-Draft für die Rookies.'),
                trailing: const _Chevron(),
                onTap: () => _confirmRollover(context, ref, l),
              ),
            ], farbe: _grpAdmin),
          ],

          if (isOwner) ...[
            _Section('Admin', farbe: _grpAdmin),
            _settingsGroup(context, [
              ListTile(
                leading: Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Mitglieder & Kader verwalten'),
                subtitle: const Text(
                    'Kicken, verwaiste Teams zuweisen, Kader bearbeiten'),
                trailing: const _Chevron(),
                onTap: () => open(FantasyAdminScreen(league: l)),
              ),
            ], farbe: _grpAdmin),
          ],

          // Ligainternes Tippspiel nachträglich einschalten (nur wenn es beim
          // Erstellen nicht gewählt wurde und noch keines aktiviert ist).
          if (isOwner &&
              !l.tipEnabled &&
              ref.watch(fantasyTipRoundProvider(l.id)).valueOrNull == null) ...[
            _Section('Tippspiel', farbe: _grpRegeln),
            _settingsGroup(context, [
              ListTile(
                leading:
                    Icon(Icons.emoji_events_outlined),
                title: const Text('Ligainternes Tippspiel einschalten'),
                subtitle: const Text(
                    'Blendet die Tippspiel-Option auf der Übersicht ein.'),
                trailing: const _Chevron(),
                onTap: () => _enableTip(context, ref, l),
              ),
            ], farbe: _grpRegeln),
          ],

          _Section('Gefahrenzone', farbe: _grpGefahr),
          _settingsGroup(context, [
            if (isOwner) ...[
              // Admin kann verlassen, muss dabei die Adminrechte übergeben.
              ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text('Liga verlassen',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Adminrechte an ein Mitglied übergeben und aussteigen — '
                    'dein Team bleibt als verwaister Slot bestehen.'),
                onTap: () => _confirmLeaveAsOwner(context, ref, l),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text('Liga löschen',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Entfernt die Liga endgültig — mit Draft, Kadern und allen '
                    'Daten, für alle Mitglieder.'),
                onTap: () => _confirmDelete(context, ref, l),
              ),
            ] else
              ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text('Liga verlassen',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Du steigst aus — dein Team bleibt als verwaister Slot '
                    'bestehen und kann neu zugewiesen werden.'),
                onTap: () => _confirmLeave(context, ref, l),
              ),
          ], farbe: _grpGefahr),

          // Mitspieler einladen — ganz unten.
          _Section('Einladen'),
          _InviteBanner(code: l.inviteCode),
        ],
      ),
    );
  }

  Future<void> _confirmLeave(
      BuildContext context, WidgetRef ref, FantasyLeague l) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liga verlassen?'),
        content: Text(
            'Du verlässt „${l.name}". Dein Team bleibt als verwaister Slot '
            'bestehen — der Admin kann es einem neuen Nutzer zuweisen, der '
            'deinen Kader übernimmt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
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
      await ref.read(fantasyLeagueRepositoryProvider).leaveLeague(l.id);
      ref.invalidate(myFantasyLeaguesProvider);
      navigator.popUntil((r) => r.isFirst);
      messenger.showSnackBar(const SnackBar(content: Text('Liga verlassen.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Verlassen fehlgeschlagen: $e')));
    }
  }

  /// Admin verlässt die Liga: fragt zuerst, wer die Adminrechte bekommt, und
  /// übergibt + steigt dann atomar aus.
  Future<void> _confirmLeaveAsOwner(
      BuildContext context, WidgetRef ref, FantasyLeague l) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final myId = ref.read(currentUserProvider)?.id;
    final others =
        (ref.read(fantasyManagersProvider(l.id)).valueOrNull ??
                const <FantasyManager>[])
            .where((m) => m.userId != myId)
            .toList();
    if (others.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Kein anderes Mitglied vorhanden, dem du die '
              'Adminrechte übergeben kannst. Du kannst die Liga stattdessen '
              'löschen.')));
      return;
    }
    // Neuen Admin auswählen.
    final newOwner = await showDialog<FantasyManager>(
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
                      fallbackText: m.display,
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
    if (newOwner == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Übergeben und verlassen?'),
        content: Text('„${newOwner.display}" wird neuer Admin von „${l.name}". '
            'Du verlässt die Liga; dein Team bleibt als verwaister Slot '
            'bestehen.'),
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
          .read(fantasyLeagueRepositoryProvider)
          .transferAndLeaveLeague(l.id, newOwner.userId);
      ref.invalidate(myFantasyLeaguesProvider);
      navigator.popUntil((r) => r.isFirst);
      messenger.showSnackBar(const SnackBar(
          content: Text('Adminrechte übergeben und Liga verlassen.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Verlassen fehlgeschlagen: $e')));
    }
  }

  Future<void> _confirmRollover(
      BuildContext context, WidgetRef ref, FantasyLeague l) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Saison ${l.season + 1}/${(l.season + 2) % 100} starten?'),
        content: const Text(
            'Der komplette Kader bleibt erhalten. Der bisherige Draft-Verlauf '
            'und offene Waiver-Anträge werden zurückgesetzt. Danach kannst du '
            'den neuen U20-Draft starten. Das kann nicht rückgängig gemacht '
            'werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Saison starten'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(draftRepositoryProvider).rolloverSeason(l.id);
      ref.invalidate(draftLeagueProvider(l.id));
      ref.invalidate(myFantasyLeaguesProvider);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Saison ${l.season + 1}/${(l.season + 2) % 100} gestartet — '
              'jetzt den U20-Draft starten.')));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Rollover fehlgeschlagen: $e')));
    }
  }

  /// Schaltet das ligainterne Tippspiel ein (die eigentliche Einrichtung läuft
  /// dann über den Button auf der Übersicht).
  Future<void> _enableTip(
      BuildContext context, WidgetRef ref, FantasyLeague l) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fantasyLeagueRepositoryProvider).setTipEnabled(l.id, true);
      ref.invalidate(draftLeagueProvider(l.id));
      ref.invalidate(myFantasyLeaguesProvider);
      messenger.showSnackBar(const SnackBar(
          content: Text('Tippspiel eingeschaltet — auf der Übersicht kannst '
              'du es einrichten.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, FantasyLeague l) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Gekoppeltes ligainternes Tippspiel (falls aktiviert).
    final tipRound = ref.read(fantasyTipRoundProvider(l.id)).valueOrNull;

    final bool alsoDeleteTip;
    if (tipRound == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Liga löschen?'),
          content: Text(
              '„${l.name}" wird mit allen Drafts, Kadern und Daten endgültig '
              'gelöscht. Das kann nicht rückgängig gemacht werden.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      alsoDeleteTip = false;
    } else {
      // Mit gekoppeltem Tippspiel: Wahl, ob es mitgelöscht wird oder bestehen
      // bleibt (dann als eigenständige Tipprunde).
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Liga löschen?'),
          content: Text(
              '„${l.name}" wird mit allen Drafts, Kadern und Daten endgültig '
              'gelöscht.\n\nZur Liga gehört das Tippspiel „${tipRound.name}". '
              'Behältst du es, bleibt es als eigenständige Tipprunde bestehen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('keep'),
              child: const Text('Tippspiel behalten'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop('both'),
              child: const Text('Beides löschen'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      alsoDeleteTip = choice == 'both';
    }

    try {
      // Tippspiel zuerst löschen (falls gewünscht), dann die Liga. Beim
      // Behalten entkoppelt der FK (ON DELETE SET NULL) die Runde automatisch.
      if (alsoDeleteTip && tipRound != null) {
        await ref.read(tipRoundRepositoryProvider).deleteRound(tipRound.id);
      }
      await ref.read(fantasyLeagueRepositoryProvider).deleteLeague(l.id);
      ref.invalidate(myFantasyLeaguesProvider);
      if (tipRound != null) {
        ref.invalidate(fantasyTipRoundProvider(l.id));
        ref.invalidate(myRoundsProvider);
      }
      navigator.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(
          content: Text(alsoDeleteTip
              ? 'Liga und Tippspiel gelöscht.'
              : 'Liga gelöscht.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    }
  }
}

// ===========================================================================
// Draft-Einstellungen
// ===========================================================================

class DraftSettingsPage extends ConsumerStatefulWidget {
  const DraftSettingsPage({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<DraftSettingsPage> createState() => _DraftSettingsPageState();
}

class _DraftSettingsPageState extends ConsumerState<DraftSettingsPage> {
  static const _minRounds = 14;
  static const _maxRounds = 30;
  static const _minU20Rounds = 1;
  static const _maxU20Rounds = 10;

  late DraftPickTime _pickTime;
  late int _rounds;
  late int _u20Rounds;
  late String _orderMode;
  late bool _pauseOn;
  late TimeOfDay _pauseStart;
  late TimeOfDay _pauseEnd;
  bool _saving = false;

  bool get _isDynasty => widget.league.mode == FantasyMode.dynasty;

  @override
  void initState() {
    super.initState();
    final l = widget.league;
    _pickTime = l.pickTime;
    _rounds = l.rounds.clamp(_minRounds, _maxRounds);
    _u20Rounds = l.u20Rounds.clamp(_minU20Rounds, _maxU20Rounds);
    _orderMode = l.draftOrderMode;
    _pauseOn = l.hasPause;
    _pauseStart = _fromMinute(l.pauseStart ?? 23 * 60);
    _pauseEnd = _fromMinute(l.pauseEnd ?? 8 * 60);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(fantasyLeagueRepositoryProvider).updateDraftSettings(
            widget.league.id,
            pickTime: _pickTime,
            roster: widget.league.roster.withRounds(_rounds),
            pauseStart: _pauseOn ? _toMinute(_pauseStart) : null,
            pauseEnd: _pauseOn ? _toMinute(_pauseEnd) : null,
            orderMode: _orderMode,
            u20Rounds: _isDynasty ? _u20Rounds : null,
          );
      ref.invalidate(draftLeagueProvider(widget.league.id));
      ref.invalidate(myFantasyLeaguesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Gespeichert')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = _editable(ref, widget.league);
    return Scaffold(
      appBar: AppBar(title: const Text('Draft-Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!editable) _LockNote(league: widget.league, ref: ref),
          _CardColumn([
            _SettingRow(
              icon: Icons.timer,
              label: 'Pickzeit',
              child: editable
                  ? DropdownButton<DraftPickTime>(
                      value: _pickTime,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final t in DraftPickTime.values)
                          DropdownMenuItem(
                            value: t,
                            child: Text(
                                '${t.label} · ${t.isLive ? 'Live' : 'Slow'}'),
                          ),
                      ],
                      onChanged: (t) => setState(() => _pickTime = t!),
                    )
                  : _ReadValue(
                      '${_pickTime.label} · ${_pickTime.isLive ? 'Live' : 'Slow'}'),
            ),
            const Divider(height: 1),
            _SettingRow(
              icon: Icons.numbers,
              label: 'Anzahl Runden',
              subtitle: '11 in der Startelf + ${_rounds - 11} auf der Bank',
              child: editable
                  ? WertStepper(
                      label: 'Anzahl Runden',
                      value: _rounds,
                      min: _minRounds,
                      max: _maxRounds,
                      onChanged: (v) => setState(() => _rounds = v))
                  : _ReadValue('$_rounds'),
            ),
          ]),
          // U20-Draft nur im Dynasty-Modus: Anzahl der Rookie-Runden pro Saison.
          if (_isDynasty) ...[
            const SizedBox(height: 8),
            _CardColumn([
              _SettingRow(
                icon: Icons.auto_awesome,
                label: 'U20-Draft-Runden',
                subtitle:
                    'Rookies je Manager pro Saison (nach dem Saison-Rollover)',
                child: editable
                    ? WertStepper(
                        label: 'U20-Draft-Runden',
                        value: _u20Rounds,
                        min: _minU20Rounds,
                        max: _maxU20Rounds,
                        onChanged: (v) => setState(() => _u20Rounds = v))
                    : _ReadValue('$_u20Rounds'),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          _CardColumn([
            _SettingRow(
              icon: Icons.format_list_numbered,
              label: 'Reihenfolge',
              child: editable
                  ? PillSelector<String>(
                      options: const {'auto': 'Zufällig', 'manual': 'Manuell'},
                      value: _orderMode,
                      onSelect: (v) => setState(() => _orderMode = v),
                    )
                  : _ReadValue(_orderMode == 'manual' ? 'Manuell' : 'Zufällig'),
            ),
            if (_orderMode == 'manual') ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.swap_vert),
                title: const Text('Reihenfolge festlegen'),
                subtitle: const Text('Teilnehmer per Ziehen anordnen'),
                trailing: const _Chevron(),
                enabled: editable,
                onTap: editable
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DraftOrderPage(league: widget.league)))
                    : null,
              ),
            ],
          ]),
          const SizedBox(height: 8),
          _CardColumn([
            SwitchListTile(
              value: _pauseOn,
              onChanged: editable ? (v) => setState(() => _pauseOn = v) : null,
              secondary: Icon(Icons.nightlight_outlined),
              title: const Text('Slow-Draft-Pause'),
              subtitle: const Text(
                  'In diesem Zeitfenster (z. B. nachts) wird kein Pick '
                  'automatisch gesetzt.'),
            ),
            if (_pauseOn) ...[
              const Divider(height: 1),
              _TimeRow(
                  label: 'Von',
                  time: _pauseStart,
                  enabled: editable,
                  onPick: (t) => setState(() => _pauseStart = t)),
              _TimeRow(
                  label: 'Bis',
                  time: _pauseEnd,
                  enabled: editable,
                  onPick: (t) => setState(() => _pauseEnd = t)),
            ],
          ]),
          if (editable) ...[
            const SizedBox(height: 20),
            _SaveButton(saving: _saving, onPressed: _save),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Liga-Einstellungen
// ===========================================================================

class LeagueSettingsPage extends ConsumerStatefulWidget {
  const LeagueSettingsPage({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<LeagueSettingsPage> createState() => _LeagueSettingsPageState();
}

class _LeagueSettingsPageState extends ConsumerState<LeagueSettingsPage> {
  static const _minTeams = 2;
  static const _maxTeamsCap = 18;

  late bool _limitTeams;
  late int _maxTeams;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.league;
    _limitTeams = l.maxTeams != null;
    _maxTeams = (l.maxTeams ?? 12).clamp(_minTeams, _maxTeamsCap);
  }

  /// Kleinste zulässige Teilnehmerzahl: nie unter die, die schon drin sind.
  /// Ein Limit von 4 in einer Liga mit sechs Teams wäre keine Einstellung,
  /// sondern ein Widerspruch — die sechs bleiben ja.
  int _untergrenze(int mitglieder) =>
      mitglieder > _minTeams ? mitglieder : _minTeams;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(fantasyLeagueRepositoryProvider).updateLeagueSettings(
            widget.league.id,
            maxTeams: _limitTeams ? _maxTeams : null,
          );
      ref.invalidate(draftLeagueProvider(widget.league.id));
      ref.invalidate(myFantasyLeaguesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Gespeichert')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.league;
    final editable = _editable(ref, l);
    final mitglieder =
        ref.watch(fantasyManagersProvider(l.id)).valueOrNull?.length ?? 0;
    final untergrenze = _untergrenze(mitglieder);
    // Der gemerkte Wert kann unter der Grenze liegen, wenn seit dem Öffnen
    // jemand beigetreten ist.
    if (_maxTeams < untergrenze) _maxTeams = untergrenze;
    return Scaffold(
      appBar: AppBar(title: const Text('Teilnehmerzahl')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!editable) _LockNote(league: l, ref: ref),
          _CardColumn([
            SwitchListTile(
              value: _limitTeams,
              onChanged:
                  editable ? (v) => setState(() => _limitTeams = v) : null,
              secondary: Icon(Icons.groups),
              title: const Text('Teilnehmer begrenzen'),
              subtitle: Text(_limitTeams
                  ? 'Höchstens $_maxTeams Teilnehmer'
                  : 'Standard: max. 18 Teilnehmer'),
            ),
            if (_limitTeams) ...[
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.person,
                label: 'Max. Teilnehmer',
                child: editable
                    ? WertStepper(
                        label: 'Max. Teilnehmer',
                        value: _maxTeams,
                        min: untergrenze,
                        max: _maxTeamsCap,
                        onChanged: (v) => setState(() => _maxTeams = v))
                    : _ReadValue('$_maxTeams'),
              ),
              if (editable && untergrenze > _minTeams) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: _Note(mitglieder == 1
                      ? 'Ein Team ist schon in der Liga — darunter geht es nicht.'
                      : '$mitglieder Teams sind schon in der Liga — darunter '
                          'geht es nicht.'),
                ),
              ],
            ],
          ]),
          const SizedBox(height: 8),
          _CardColumn([
            _SettingRow(
                icon: Icons.auto_awesome,
                label: 'Modus',
                child: _ReadValue(l.mode.label)),
            const Divider(height: 1),
            _SettingRow(
                icon: Icons.calendar_today,
                label: 'Saison',
                child:
                    _ReadValue('${l.season}/${(l.season + 1) % 100}')),
          ]),
          if (editable) ...[
            const SizedBox(height: 20),
            _SaveButton(saving: _saving, onPressed: _save),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Playoff-Einstellungen
// ===========================================================================

class PlayoffSettingsPage extends ConsumerStatefulWidget {
  const PlayoffSettingsPage({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<PlayoffSettingsPage> createState() =>
      _PlayoffSettingsPageState();
}

class _PlayoffSettingsPageState extends ConsumerState<PlayoffSettingsPage> {
  static const _minTeams = 4;
  static const _maxTeams = 8;
  static const _minOffset = 5;
  static const _maxOffset = 10;

  late int _teams;
  late int _weeks;
  late int _offset;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.league;
    _teams = (l.playoffTeams ?? 4).clamp(_minTeams, _maxTeams);
    _weeks = l.playoffWeeks ?? 1;
    _offset = (l.tradeDeadlineOffset ?? _minOffset).clamp(_minOffset, _maxOffset);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(fantasyLeagueRepositoryProvider).updatePlayoffSettings(
            widget.league.id,
            teams: _teams,
            weeks: _weeks,
            tradeDeadlineOffset: _offset,
          );
      ref.invalidate(draftLeagueProvider(widget.league.id));
      ref.invalidate(myFantasyLeaguesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Gespeichert')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = _editable(ref, widget.league);
    final plan = computePlayoffPlan(
        teams: _teams, weeksPerRound: _weeks, tradeDeadlineOffset: _offset);

    return Scaffold(
      appBar: AppBar(title: const Text('Playoff-Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!editable) _LockNote(league: widget.league, ref: ref),
          _PlayoffSummary(plan: plan),
          const SizedBox(height: 14),
          _CardColumn([
            _SettingRow(
              icon: Icons.emoji_events_outlined,
              label: 'Playoff-Teams',
              subtitle: _teams.isOdd
                  ? 'Ungerade — Platz 1 bekommt ein Freilos'
                  : null,
              child: editable
                  ? WertStepper(
                      label: 'Playoff-Teams',
                      value: _teams,
                      min: _minTeams,
                      max: _maxTeams,
                      onChanged: (v) => setState(() => _teams = v))
                  : _ReadValue('$_teams'),
            ),
            const Divider(height: 1),
            _SettingRow(
              icon: Icons.date_range,
              label: 'Partie-Dauer',
              child: editable
                  ? PillSelector<int>(
                      options: const {1: '1 Woche', 2: '2 Wochen'},
                      value: _weeks,
                      onSelect: (v) => setState(() => _weeks = v),
                    )
                  : _ReadValue(_weeks == 2 ? '2 Wochen' : '1 Woche'),
            ),
            const Divider(height: 1),
            _SettingRow(
              icon: Icons.swap_horiz,
              label: 'Trade-Deadline',
              subtitle: 'Spieltage vor Playoff-Start (5–10)',
              child: editable
                  ? WertStepper(
                      label: 'Trade-Deadline',
                      value: _offset,
                      min: _minOffset,
                      max: _maxOffset,
                      onChanged: (v) => setState(() => _offset = v))
                  : _ReadValue('$_offset'),
            ),
          ]),
          if (editable) ...[
            const SizedBox(height: 20),
            _SaveButton(
                saving: _saving, onPressed: plan.isValid ? _save : null),
          ],
        ],
      ),
    );
  }
}

/// Farbige Zusammenfassung des berechneten Playoff-Plans.
class _PlayoffSummary extends StatelessWidget {
  const _PlayoffSummary({required this.plan});
  final PlayoffPlan plan;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFC83D); // MatchUp-Gold für Playoffs
    final scheme = Theme.of(context).colorScheme;
    if (!plan.isValid) {
      return _Note('Diese Kombination passt nicht in die ${plan.totalMatchdays} '
          'Spieltage — weniger Teams, kürzere Partien oder eine frühere '
          'Deadline wählen.');
    }
    Widget line(IconData icon, String text, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: strong
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.75],
          colors: [
            Color.alphaBlend(
                accent.withValues(alpha: 0.12), Theme.of(context).cardColor),
            Theme.of(context).cardColor,
          ],
        ),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Playoff-Plan',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          line(Icons.account_tree_outlined,
              '${plan.rounds} Runden × ${plan.weeksPerRound == 2 ? '2 Wochen' : '1 Woche'}'),
          line(Icons.play_arrow, 'Playoffs starten an Spieltag ${plan.startRound}',
              strong: true),
          line(Icons.swap_horiz,
              'Trade-Deadline: Spieltag ${plan.tradeDeadlineRound}'),
          if (plan.topSeedBye)
            line(Icons.workspace_premium_outlined,
                'Platz 1: Freilos (Bye Week), eine Runde weiter'),
          const SizedBox(height: 4),
          Text('Reguläre Saison: ${plan.totalMatchdays} Spieltage',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Manuelle Draft-Reihenfolge
// ===========================================================================

class DraftOrderPage extends ConsumerStatefulWidget {
  const DraftOrderPage({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<DraftOrderPage> createState() => _DraftOrderPageState();
}

class _DraftOrderPageState extends ConsumerState<DraftOrderPage> {
  List<FantasyManager>? _order;
  bool _saving = false;

  Future<void> _save() async {
    final order = _order;
    if (order == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final repo = ref.read(fantasyLeagueRepositoryProvider);
      await repo.setDraftOrder(
          widget.league.id, [for (final m in order) m.userId]);
      // Festgelegte Reihenfolge im Liga-Chat bekanntgeben (wie beim Mischen).
      final text = [
        for (final (i, m) in order.indexed) '${i + 1}. ${m.display}'
      ].join('\n');
      try {
        await repo.sendMessage(
            widget.league.id, '📋 Draft-Reihenfolge festgelegt:\n$text');
      } catch (_) {}
      ref.invalidate(fantasyManagersProvider(widget.league.id));
      ref.invalidate(draftLeagueProvider(widget.league.id));
      messenger
          .showSnackBar(const SnackBar(content: Text('Reihenfolge gespeichert')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final managersAsync = ref.watch(fantasyManagersProvider(widget.league.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Draft-Reihenfolge')),
      body: managersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (managers) {
          _order ??= [...managers]..sort((a, b) {
              final pa = a.draftPosition ?? 1 << 30;
              final pb = b.draftPosition ?? 1 << 30;
              return pa != pb
                  ? pa.compareTo(pb)
                  : a.display.toLowerCase().compareTo(b.display.toLowerCase());
            });
          final order = _order!;
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Ziehe die Teilnehmer in die gewünschte Reihenfolge. '
                  'Position 1 pickt zuerst.',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: ReorderableListView(
                  padding: const EdgeInsets.all(12),
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final item = order.removeAt(oldIndex);
                      order.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (final (i, m) in order.indexed)
                      Card(
                        key: ValueKey(m.userId),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                scheme.primary.withValues(alpha: 0.15),
                            child: Text('${i + 1}',
                                style: TextStyle(color: scheme.primary)),
                          ),
                          title: Text(m.display),
                          trailing: const Icon(Icons.drag_handle),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: managersAsync.hasValue
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Speichern'),
            )
          : null,
    );
  }
}

bool _editable(WidgetRef ref, FantasyLeague league) =>
    ref.watch(currentUserProvider)?.id == league.createdBy &&
    league.draftStatus == DraftStatus.setup;

// --- gemeinsame Bausteine ---------------------------------------------------

class _LockNote extends StatelessWidget {
  const _LockNote({required this.league, required this.ref});
  final FantasyLeague league;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(currentUserProvider)?.id == league.createdBy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Note(isOwner
          ? 'Der Draft ist gestartet — die Einstellungen sind jetzt fixiert.'
          : 'Nur der Ersteller kann die Einstellungen ändern.'),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onPressed});
  final bool saving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: (saving || onPressed == null) ? null : onPressed,
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.check),
      label: const Text('Speichern'),
    );
  }
}

/// Gruppenkopf der Einstellungen — dieselbe Kapitelmarke wie im Live-Tab, im
/// Favoriten-Tab, im Seitenmenü und in der Liga-Übersicht.
///
/// Vorher standen hier 11-Punkt-Versalien in Grau, kaum vom Untertitel der
/// Zeilen darunter zu unterscheiden: neun Zeilen ohne Takt. Der farbige Strich
/// gehört zur Gruppe darunter und wiederholt die Farbe, die ihre Symbole
/// tragen — er gliedert, statt zu schmücken.
class _Section extends StatelessWidget {
  const _Section(this.text, {this.farbe});

  final String text;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 26, 0, 8),
      child: Row(
        children: [
          if (farbe != null) ...[
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: farbe,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 0.8,
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fasst mehrere Einstellungs-Zeilen zu einer Gruppe zusammen — flach, nur
/// Haarlinien dazwischen.
///
/// [farbe] färbt die Symbole der Gruppe. Vorher trug **jedes** Symbol des
/// Schirms das Markengrün: neun grüne Punkte untereinander, obwohl Grün in
/// dieser App „hier läuft etwas" heißt und hier nichts läuft. Eine Farbe je
/// Gruppe trennt die Bereiche, statt neunmal dasselbe Signal zu geben.
///
/// Die Zeilen sind außerdem nicht mehr `dense`: Titel 16 statt 14, Untertitel
/// deutlich leiser — vorher waren beide fast gleich groß, und ausgerechnet der
/// Untertitel trägt die Auskunft (den aktuellen Wert).
Widget _settingsGroup(
  BuildContext context,
  List<Widget> tiles, {
  Color? farbe,
}) {
  final scheme = Theme.of(context).colorScheme;
  final ton = farbe ?? scheme.primary;
  return IconTheme.merge(
    data: IconThemeData(color: ton, size: 22),
    child: ListTileTheme(
      data: ListTileThemeData(
        dense: false,
        // `iconColor` und nicht `IconTheme`: `ListTile` löst die Farbe seiner
        // führenden Symbole selbst auf und überstimmt die umgebende
        // `IconTheme` — die Gruppenfarbe kam damit nie an.
        iconColor: ton,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        minVerticalPadding: 10,
        // **Aus dem Theme abgeleitet, nicht neu gebaut.** Ein blankes
        // `TextStyle` erbt die `fontFamily` nicht — die Zeilen wären auf
        // Roboto zurückgefallen statt Barlow Condensed zu benutzen, und zwar
        // auf dem Gerät genauso wie in der Vorschau.
        titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.25,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 44,
                color: scheme.onSurface.withValues(alpha: 0.07),
              ),
            tiles[i],
          ],
        ],
      ),
    ),
  );
}

/// Das Chevron am Zeilenende bleibt grau. `ListTileThemeData.iconColor` färbt
/// führende **und** folgende Symbole; in der Gruppenfarbe wären die Chevrons
/// eine zweite Farbspur, die nichts unterscheidet.
class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right,
    size: 20,
    color: Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
  );
}

/// Farben der Einstellungs-Gruppen. Eine je Bereich — sie steht im Strich des
/// Gruppenkopfs und in den Symbolen darunter.
const _grpLiga = MatchUpColors.green;
const _grpTeam = Color(0xFF4FC3A1);
const _grpRegeln = Color(0xFFFFC83D);
const _grpAdmin = Color(0xFF5B9DF9);
const _grpGefahr = MatchUpColors.red;


/// **Kader-Limits je Position.**
///
/// Nicht die Formation (wie viele in der *Elf* stehen dürfen — das sind
/// `defMin`/`defMax` und Geschwister), sondern der **Kader**: wie viele
/// Spieler einer Position man überhaupt besitzen darf.
///
/// Anlass war ein Manager mit acht Stürmern und drei Abwehrspielern. Ihm blieb
/// bei ABW 3–5 genau eine mögliche Aufstellung; fällt ein Verteidiger aus,
/// keine mehr. Fünf Kaderplätze waren tot.
///
/// Zwei Entscheidungen, die man sehen können muss:
///  * **Vorgabe ist „aus".** Als das entstand, liefen zwei Drafts. Eine
///    stillschweigend eingeführte Obergrenze hätte sie mitten im Lauf
///    blockiert.
///  * **Änderbar auch nach dem Draft** — anders als Rundenzahl und Pickzeit.
///    Limits regeln Free Agency, Waiver und Trades, also die ganze Saison.
/// Untertitel der Kader-Limit-Zeile: „TW 2 · ABW 6 · MF 6 · ST 5" oder der
/// Hinweis, dass keine Grenze gilt.
String _kaderLimitText(RosterConfig r) {
  if (r.maxGk == null &&
      r.maxDef == null &&
      r.maxMid == null &&
      r.maxFwd == null) {
    return 'Keine Obergrenze je Position';
  }
  String t(String k, int? v) => '$k ${v ?? '∞'}';
  return '${t('TW', r.maxGk)} · ${t('ABW', r.maxDef)} · '
      '${t('MF', r.maxMid)} · ${t('ST', r.maxFwd)}';
}

class KaderLimitsPage extends ConsumerStatefulWidget {
  const KaderLimitsPage({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<KaderLimitsPage> createState() => _KaderLimitsPageState();
}

class _KaderLimitsPageState extends ConsumerState<KaderLimitsPage> {
  /// Limit je Position, `null` = keine Einschränkung. Jede Position steht für
  /// sich: Man kann die Torhüter deckeln und Mittelfeld und Sturm offen lassen.
  final _limit = <PlayerPosition, int?>{};
  bool _saving = false;

  RosterConfig get _r => widget.league.roster;

  @override
  void initState() {
    super.initState();
    final r = _r;
    for (final pos in PlayerPosition.values) {
      _limit[pos] = r.limitFor(pos);
    }
  }

  bool get _irgendeins => _limit.values.any((v) => v != null);

  RosterConfig get _neu => RosterConfig(
        gk: _r.gk,
        def: _r.def,
        mid: _r.mid,
        fwd: _r.fwd,
        bench: _r.bench,
        defMin: _r.defMin,
        defMax: _r.defMax,
        midMin: _r.midMin,
        midMax: _r.midMax,
        fwdMin: _r.fwdMin,
        fwdMax: _r.fwdMax,
        maxGk: _limit[PlayerPosition.gk],
        maxDef: _limit[PlayerPosition.def],
        maxMid: _limit[PlayerPosition.mid],
        maxFwd: _limit[PlayerPosition.fwd],
      );

  /// Beides kommt aus dem Editor — er trägt die Regel, nicht dieser Schirm.
  bool get _reichtFuerKader =>
      KaderLimitsEditor.reichtFuerKader(_r, _limit);

  String _hinweisText() => KaderLimitsEditor.hinweisText(_r, _limit);

  Future<void> _speichern() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .updateRosterLimits(widget.league.id, _neu);
      ref.invalidate(draftLeagueProvider(widget.league.id));
      ref.invalidate(myFantasyLeaguesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Gespeichert')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Wie viele Kader liegen mit den neuen Limits schon darüber?
  ///
  /// Sie brechen nicht — der Trigger prüft nur beim Hinzufügen. Aber wer ein
  /// Limit setzt, sollte wissen, dass es für manche sofort greift.
  int _schonDarueber() {
    if (!_irgendeins) return 0;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    final roster = ref.watch(leagueRosterProvider(widget.league.id)).valueOrNull;
    if (pool == null || roster == null) return 0;
    final posOf = {for (final p in pool) p.id: p.position};
    final proManager = <String, Map<PlayerPosition, int>>{};
    for (final e in roster) {
      final pos = posOf[e.playerId];
      if (pos == null) continue;
      final m = proManager.putIfAbsent(e.managerId, () => {});
      m[pos] = (m[pos] ?? 0) + 1;
    }
    // Offene Positionen (`null`) zählen nicht mit — dort gibt es nichts zu
    // reißen.
    return proManager.values
        .where((m) => _limit.entries.any(
            (l) => l.value != null && (m[l.key] ?? 0) > l.value!))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final darueber = _schonDarueber();
    return Scaffold(
      appBar: AppBar(title: const Text('Kader-Limits')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Höchstens so viele Spieler einer Position im Kader. Gilt beim '
              'Draften, in der Free Agency, bei Waivern und Trades — nicht für '
              'die Aufstellung, die regelt die Formation.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          // **Derselbe Editor wie beim Erstellen der Liga.** Er trägt die
          // Regeln (Untergrenze je Position, Vorschlag beim Einschalten, wann
          // die Summe reichen muss); zwei Fassungen davon liefen beim nächsten
          // Feinschliff auseinander.
          _CardColumn([
            KaderLimitsEditor(
              roster: _r,
              limits: _limit,
              onChanged: (neu) => setState(() {
                _limit
                  ..clear()
                  ..addAll(neu);
              }),
            ),
          ]),
          const SizedBox(height: 12),
          _Hinweis(gut: _reichtFuerKader, text: _hinweisText()),
          if (darueber > 0) ...[
            const SizedBox(height: 8),
            _Hinweis(
              gut: true,
              text: darueber == 1
                  ? 'Ein Kader liegt schon über einem Limit. Er behält seine '
                      'Spieler — es kommen nur keine mehr dazu.'
                  : '$darueber Kader liegen schon über einem Limit. Sie '
                      'behalten ihre Spieler — es kommen nur keine mehr dazu.',
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_saving || !_reichtFuerKader) ? null : _speichern,
            child: Text(_saving ? 'Speichere …' : 'Speichern'),
          ),
        ],
      ),
    );
  }
}

class _Hinweis extends StatelessWidget {
  const _Hinweis({required this.gut, required this.text});

  final bool gut;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farbe = gut ? scheme.onSurfaceVariant : scheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(gut ? Icons.info_outline : Icons.error_outline,
            size: 16, color: farbe),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: farbe)),
        ),
      ],
    );
  }
}

class _CardColumn extends StatelessWidget {
  const _CardColumn(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow(
      {required this.icon,
      required this.label,
      required this.child,
      this.subtitle});

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: child,
    );
  }
}

class _ReadValue extends StatelessWidget {
  const _ReadValue(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w600));
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow(
      {required this.label,
      required this.time,
      required this.enabled,
      required this.onPick});

  final String label;
  final TimeOfDay time;
  final bool enabled;
  final ValueChanged<TimeOfDay> onPick;

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 4),
      title: Text(label),
      trailing: OutlinedButton(
        onPressed: enabled
            ? () async {
                final picked =
                    await showTimePicker(context: context, initialTime: time);
                if (picked != null) onPick(picked);
              }
            : null,
        child: Text(_fmt(time),
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
      ),
    );
  }
}

TimeOfDay _fromMinute(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);
int _toMinute(TimeOfDay t) => t.hour * 60 + t.minute;

/// Kompakte Kennzahl-Kachel (Teilnehmer / Kadergröße / Startelf).
/// Hervorgehobener Einladungscode zum Kopieren.
class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Einladungscode kopiert')));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.key),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Einladungscode',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                    Text(code,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                  ],
                ),
              ),
              Icon(Icons.copy, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
