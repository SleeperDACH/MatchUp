import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'draft_room_screen.dart';
import 'fantasy_settings_screen.dart';
import 'fantasy_table_screen.dart';
import 'free_agency_screen.dart';
import 'lineup_screen.dart';
import 'matchups_screen.dart';
import 'my_team_screen.dart';
import 'player_flag.dart';
import 'player_pool_screen.dart';

/// Vollwertiger Fantasy-Liga-Screen mit Tabs. Zeigt schon vor dem Draft
/// Tabelle, Teilnehmer und (leeren) Kader an; die Übersicht führt durch
/// Setup und Draft.
class FantasyLeagueScreen extends ConsumerWidget {
  const FantasyLeagueScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Live-Status, damit Draft-Änderungen sofort durchschlagen.
    final live = ref.watch(draftLeagueProvider(league.id)).valueOrNull ?? league;
    final isAdmin = ref.watch(currentUserProvider)?.id == league.createdBy;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              Text(live.name),
              Text(
                '${live.mode.label} · Saison ${live.season}/${(live.season + 1) % 100}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.primary),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Einstellungen',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FantasyLeagueSettingsScreen(league: live))),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Übersicht'),
              Tab(text: 'Tabelle'),
              Tab(text: 'Kader'),
              Tab(text: 'Matchups'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(league: live, isAdmin: isAdmin),
            FantasyTableBody(league: live),
            _RostersTab(league: live),
            MatchupsBody(league: live),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Übersicht
// ---------------------------------------------------------------------------

// Akzentfarben für die Übersicht (MatchUp-Palette + abgestimmte Töne).
const _cGreen = Color(0xFF4ADE6A);
const _cTeal = Color(0xFF4FC3A1);
const _cAmber = Color(0xFFFFC83D);
const _cRed = Color(0xFFF23030);
const _cBase = Color(0xFF12141C);

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.league, required this.isAdmin});

  final FantasyLeague league;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = league.draftStatus == DraftStatus.setup;
    final drafted = !setup;
    final managers =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull?.length;
    final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusHero(league: league),
        const SizedBox(height: 14),
        _draftButton(context, ref, league, isAdmin),
        const SizedBox(height: 18),
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
                value: '${league.roster.squadSize}',
                label: 'Kadergröße',
                color: _cTeal),
            const SizedBox(width: 10),
            _StatPill(
                icon: Icons.sports_soccer,
                value: '${league.roster.starters}',
                label: 'Startelf',
                color: _cAmber),
          ],
        ),
        if (setup) ...[
          const SizedBox(height: 16),
          _InviteBanner(code: league.inviteCode),
        ],
        const SizedBox(height: 24),
        Text('Schnellzugriff', style: labelStyle),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            if (drafted) ...[
              _ActionTile(
                icon: Icons.sports_soccer,
                label: 'Aufstellung',
                color: _cGreen,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LineupScreen(league: league))),
              ),
              _ActionTile(
                icon: Icons.shield_outlined,
                label: 'Mein Team',
                color: _cTeal,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MyTeamScreen(league: league))),
              ),
              _ActionTile(
                icon: Icons.person_add_alt,
                label: 'Free Agency',
                color: _cAmber,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FreeAgencyScreen(league: league))),
              ),
            ],
            _ActionTile(
              icon: Icons.groups_2,
              label: 'Spielerpool',
              color: _cRed,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerPoolScreen())),
            ),
          ],
        ),
      ],
    );
  }

  Widget _draftButton(
      BuildContext context, WidgetRef ref, FantasyLeague live, bool isAdmin) {
    void openRoom() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DraftRoomScreen(league: live)));

    Future<void> run(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      try {
        await action();
        ref.invalidate(fantasyManagersProvider(live.id));
        ref.invalidate(draftLeagueProvider(live.id));
        navigator.push(
            MaterialPageRoute(builder: (_) => DraftRoomScreen(league: live)));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      }
    }

    final dynasty = live.mode == FantasyMode.dynasty;
    final repo = ref.read(draftRepositoryProvider);

    switch (live.draftStatus) {
      case DraftStatus.setup:
        if (!isAdmin) {
          return const _DisabledHint(
              icon: Icons.hourglass_empty,
              text: 'Warten auf den Draft-Start durch den Admin');
        }
        return FilledButton.icon(
          icon: const Icon(Icons.sports),
          label: Text(dynasty ? 'Haupt-Draft starten' : 'Draft starten'),
          onPressed: () => run(() => repo.startDraft(live.id)),
        );
      case DraftStatus.drafting:
        return FilledButton.icon(
          icon: const Icon(Icons.sports),
          label: Text(dynasty ? 'Zum ${live.draftPhase.label}' : 'Zum Draft'),
          onPressed: openRoom,
        );
      case DraftStatus.done:
        if (dynasty && live.draftPhase == DraftPhase.startup) {
          if (!isAdmin) {
            return const _DisabledHint(
                icon: Icons.hourglass_empty,
                text: 'Haupt-Draft beendet — der Admin startet den U20-Draft');
          }
          return FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('U20-Draft starten'),
            onPressed: () => run(() => repo.startU20Draft(live.id)),
          );
        }
        return OutlinedButton.icon(
          icon: const Icon(Icons.emoji_events),
          label: const Text('Draft-Ergebnis'),
          onPressed: openRoom,
        );
    }
  }
}

/// Farbiger Status-Kopf: zeigt die aktuelle Phase der Liga mit Akzentfarbe.
class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.league});

  final FantasyLeague league;

  ({Color color, IconData icon, String title, String subtitle}) _info() {
    switch (league.draftStatus) {
      case DraftStatus.setup:
        return (
          color: _cAmber,
          icon: Icons.hourglass_top,
          title: 'Setup',
          subtitle: 'Lade Freunde ein und starte den Draft.'
        );
      case DraftStatus.drafting:
        return (
          color: _cGreen,
          icon: Icons.sports,
          title: 'Draft läuft',
          subtitle: 'Der Draft ist gerade im Gange.'
        );
      case DraftStatus.done:
        if (league.mode == FantasyMode.dynasty &&
            league.draftPhase == DraftPhase.startup) {
          return (
            color: _cTeal,
            icon: Icons.auto_awesome,
            title: 'Haupt-Draft beendet',
            subtitle: 'Als Nächstes steht der U20-Draft an.'
          );
        }
        return (
          color: _cGreen,
          icon: Icons.emoji_events,
          title: 'Saison läuft',
          subtitle: 'Stell deine Elf auf und sammle Punkte.'
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [i.color.withValues(alpha: 0.38), _cBase],
        ),
        border: Border.all(color: i.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: i.color, shape: BoxShape.circle),
            child: Icon(i.icon, color: _cBase, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(i.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Farbige Kennzahl-Pille (Teilnehmer / Kadergröße / Startelf).
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

/// Farbige Aktions-Kachel im Schnellzugriff-Raster.
class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: _cBase, size: 22),
              ),
              const Spacer(),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
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

class _DisabledHint extends StatelessWidget {
  const _DisabledHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
              child:
                  Text(text, style: TextStyle(color: scheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kader
// ---------------------------------------------------------------------------

class _RostersTab extends ConsumerWidget {
  const _RostersTab({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final myId = ref.watch(currentUserProvider)?.id;

    if (managersAsync.isLoading || poolAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = managersAsync.error ?? poolAsync.error;
    if (err != null) return Center(child: Text('Fehler: $err'));

    final managers = managersAsync.requireValue;
    final playerById = {for (final p in poolAsync.requireValue) p.id: p};
    final drafted = league.draftStatus != DraftStatus.setup;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!drafted)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Die Kader entstehen im Draft — hier siehst du sie, sobald es '
              'losgeht.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final m in managers)
          _ManagerRoster(
            name: m.username,
            isMe: m.userId == myId,
            players: [
              for (final r in roster)
                if (r.managerId == m.userId && playerById[r.playerId] != null)
                  playerById[r.playerId]!
            ],
          ),
      ],
    );
  }
}

class _ManagerRoster extends StatelessWidget {
  const _ManagerRoster(
      {required this.name, required this.isMe, required this.players});

  final String name;
  final bool isMe;
  final List<FantasyPlayer> players;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: isMe,
        title: Text(name,
            style: isMe ? const TextStyle(fontWeight: FontWeight.bold) : null),
        subtitle: Text('${players.length} Spieler',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: players.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('Noch keine Spieler.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ]
            : [
                for (final pos in PlayerPosition.values)
                  ..._positionGroup(context, pos, players),
              ],
      ),
    );
  }

  List<Widget> _positionGroup(
      BuildContext context, PlayerPosition pos, List<FantasyPlayer> all) {
    final inPos = all.where((p) => p.position == pos).toList();
    if (inPos.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Text(pos.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
      for (final p in inPos)
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: PlayerFlag(code: p.nationality),
          title: Text(p.name),
          subtitle: Text(p.club),
        ),
    ];
  }
}
