import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/playoff.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'fantasy_admin_screen.dart';

// Akzentfarben für die Liga-Info-Kacheln.
const _cGreen = Color(0xFF4ADE6A);
const _cTeal = Color(0xFF4FC3A1);
const _cAmber = Color(0xFFFFC83D);

/// Einstellungen einer Fantasy-Liga als Menü: je Bereich eine eigene Seite.
class FantasyLeagueSettingsScreen extends ConsumerWidget {
  const FantasyLeagueSettingsScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Live-Stand, damit die Zusammenfassungen nach dem Speichern stimmen.
    final l = ref.watch(draftLeagueProvider(league.id)).valueOrNull ?? league;
    final isOwner = ref.watch(currentUserProvider)?.id == l.createdBy;
    final managers =
        ref.watch(fantasyManagersProvider(l.id)).valueOrNull?.length;

    void open(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));

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
        padding: const EdgeInsets.all(16),
        children: [
          _InviteBanner(code: l.inviteCode),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill(
                  icon: Icons.groups,
                  value: managers?.toString() ?? '–',
                  label: 'Teilnehmer',
                  color: _cGreen),
              const SizedBox(width: 10),
              _StatPill(
                  icon: Icons.badge_outlined,
                  value: '${l.roster.squadSize}',
                  label: 'Kadergröße',
                  color: _cTeal),
              const SizedBox(width: 10),
              _StatPill(
                  icon: Icons.sports_soccer,
                  value: '${l.roster.starters}',
                  label: 'Startelf',
                  color: _cAmber),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Icon(Icons.sports, color: scheme.primary),
              title: const Text('Draft-Einstellungen'),
              subtitle: Text(
                  '${l.pickTime.label} · ${l.rounds} Runden${l.hasPause ? ' · Pause' : ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(DraftSettingsPage(league: l)),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.tune, color: scheme.primary),
              title: const Text('Liga-Einstellungen'),
              subtitle: Text(l.maxTeams == null
                  ? 'Teilnehmer: unbegrenzt'
                  : 'Teilnehmer: max. ${l.maxTeams}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(LeagueSettingsPage(league: l)),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.emoji_events_outlined, color: scheme.primary),
              title: const Text('Playoff-Einstellungen'),
              subtitle: Text(l.hasPlayoffs
                  ? '${l.playoffTeams} Teams · ${l.playoffWeeks == 2 ? '2-Wochen' : '1-Wochen'}-Partien'
                  : 'noch nicht konfiguriert'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(PlayoffSettingsPage(league: l)),
            ),
          ),
          if (l.mode == FantasyMode.dynasty &&
              isOwner &&
              l.draftStatus == DraftStatus.done &&
              l.draftPhase == DraftPhase.u20) ...[
            const SizedBox(height: 24),
            _Section('Neue Saison'),
            Card(
              child: ListTile(
                leading: Icon(Icons.calendar_month, color: scheme.primary),
                title: const Text('Saison-Rollover'),
                subtitle: Text(
                    'Startet Saison ${l.season + 1}/${(l.season + 2) % 100}: '
                    'Kader bleibt, danach ein neuer U20-Draft für die Rookies.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmRollover(context, ref, l),
              ),
            ),
          ],
          if (isOwner) ...[
            const SizedBox(height: 24),
            _Section('Admin'),
            Card(
              child: ListTile(
                leading: Icon(Icons.admin_panel_settings_outlined,
                    color: scheme.primary),
                title: const Text('Mitglieder & Kader verwalten'),
                subtitle: const Text(
                    'Kicken, verwaiste Teams zuweisen, Kader bearbeiten'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(FantasyAdminScreen(league: l)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _Section('Gefahrenzone'),
          if (isOwner)
            Card(
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text('Liga löschen',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Entfernt die Liga endgültig — mit Draft, Kadern und allen '
                    'Daten, für alle Mitglieder.'),
                onTap: () => _confirmDelete(context, ref, l),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text('Liga verlassen',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Du steigst aus — dein Team bleibt als verwaister Slot '
                    'bestehen und kann neu zugewiesen werden.'),
                onTap: () => _confirmLeave(context, ref, l),
              ),
            ),
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

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, FantasyLeague l) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
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
    try {
      await ref.read(fantasyLeagueRepositoryProvider).deleteLeague(l.id);
      ref.invalidate(myFantasyLeaguesProvider);
      navigator.popUntil((r) => r.isFirst);
      messenger.showSnackBar(const SnackBar(content: Text('Liga gelöscht.')));
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

  late DraftPickTime _pickTime;
  late int _rounds;
  late String _orderMode;
  late bool _pauseOn;
  late TimeOfDay _pauseStart;
  late TimeOfDay _pauseEnd;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.league;
    _pickTime = l.pickTime;
    _rounds = l.rounds.clamp(_minRounds, _maxRounds);
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
    final scheme = Theme.of(context).colorScheme;
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
                  ? _Stepper(
                      value: _rounds,
                      min: _minRounds,
                      max: _maxRounds,
                      onChanged: (v) => setState(() => _rounds = v))
                  : _ReadValue('$_rounds'),
            ),
          ]),
          const SizedBox(height: 8),
          _CardColumn([
            _SettingRow(
              icon: Icons.format_list_numbered,
              label: 'Reihenfolge',
              child: editable
                  ? SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'auto', label: Text('Zufällig')),
                        ButtonSegment(value: 'manual', label: Text('Manuell')),
                      ],
                      selected: {_orderMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _orderMode = s.first),
                    )
                  : _ReadValue(_orderMode == 'manual' ? 'Manuell' : 'Zufällig'),
            ),
            if (_orderMode == 'manual') ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.swap_vert, color: scheme.primary),
                title: const Text('Reihenfolge festlegen'),
                subtitle: const Text('Teilnehmer per Ziehen anordnen'),
                trailing: const Icon(Icons.chevron_right),
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
              secondary: Icon(Icons.nightlight_outlined, color: scheme.primary),
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
  static const _maxTeamsCap = 20;

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
    final scheme = Theme.of(context).colorScheme;
    final l = widget.league;
    final editable = _editable(ref, l);
    return Scaffold(
      appBar: AppBar(title: const Text('Liga-Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!editable) _LockNote(league: l, ref: ref),
          _CardColumn([
            SwitchListTile(
              value: _limitTeams,
              onChanged:
                  editable ? (v) => setState(() => _limitTeams = v) : null,
              secondary: Icon(Icons.groups, color: scheme.primary),
              title: const Text('Teilnehmer begrenzen'),
              subtitle: Text(
                  _limitTeams ? 'Höchstens $_maxTeams Teilnehmer' : 'Unbegrenzt'),
            ),
            if (_limitTeams) ...[
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.person,
                label: 'Max. Teilnehmer',
                child: editable
                    ? _Stepper(
                        value: _maxTeams,
                        min: _minTeams,
                        max: _maxTeamsCap,
                        onChanged: (v) => setState(() => _maxTeams = v))
                    : _ReadValue('$_maxTeams'),
              ),
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
                  ? _Stepper(
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
                  ? SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1 Woche')),
                        ButtonSegment(value: 2, label: Text('2 Wochen')),
                      ],
                      selected: {_weeks},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _weeks = s.first),
                    )
                  : _ReadValue(_weeks == 2 ? '2 Wochen' : '1 Woche'),
            ),
            const Divider(height: 1),
            _SettingRow(
              icon: Icons.swap_horiz,
              label: 'Trade-Deadline',
              subtitle: 'Spieltage vor Playoff-Start (5–10)',
              child: editable
                  ? _Stepper(
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
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
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
      await ref.read(fantasyLeagueRepositoryProvider).setDraftOrder(
          widget.league.id, [for (final m in order) m.userId]);
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
                  : a.username.toLowerCase().compareTo(b.username.toLowerCase());
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
                          title: Text(m.username),
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

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.value,
      required this.min,
      required this.max,
      required this.onChanged});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
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
class _StatPill extends StatelessWidget {
  const _StatPill(
      {required this.icon,
      required this.value,
      required this.label,
      required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

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
              Icon(Icons.key, color: scheme.primary),
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
                            fontFamily: 'monospace',
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
