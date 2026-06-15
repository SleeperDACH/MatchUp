import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'theme.dart';

/// Liga-Übersicht: Tabelle und Spieltage eines Wettbewerbs. Aufgerufen über
/// die Liga-Chips im Live-Tab.
class LeagueOverviewScreen extends StatelessWidget {
  const LeagueOverviewScreen({super.key, required this.league});

  final LeagueInfo league;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(league.name),
          bottom: const TabBar(
            tabs: [Tab(text: 'Tabelle'), Tab(text: 'Spieltage')],
          ),
        ),
        body: TabBarView(
          children: [
            _TableTab(leagueId: league.id),
            _MatchdaysTab(leagueId: league.id),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Tabelle
// ---------------------------------------------------------------------
class _TableTab extends ConsumerWidget {
  const _TableTab({required this.leagueId});
  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = Leagues.byId(leagueId);
    // Turniere mit Gruppenphase (WM/EM): Tabelle nach Gruppen, abgeleitet aus
    // dem Gruppen-Spielplan. Sonst die offizielle (flache) Ligatabelle.
    if (league.fixedSeason != null) {
      return _GroupTables(leagueId: leagueId);
    }

    final tableAsync = ref.watch(leagueTableProvider(leagueId));
    return tableAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Retry(
        message: 'Tabelle konnte nicht geladen werden.',
        onRetry: () => ref.invalidate(leagueTableProvider(leagueId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('Noch keine Tabelle verfügbar.'));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(leagueTableProvider(leagueId)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return const _TableHeader();
              return _TableRowTile(row: rows[i - 1]);
            },
          ),
        );
      },
    );
  }
}

/// Gruppentabellen für Turniere: aus dem Gruppen-Spielplan abgeleitet
/// (Gruppen via zusammenhängender Teams) und aus den Ergebnissen berechnet.
class _GroupTables extends ConsumerWidget {
  const _GroupTables({required this.leagueId});
  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixturesAsync = ref.watch(leagueSeasonFixturesProvider(leagueId));
    return fixturesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Retry(
        message: 'Tabelle konnte nicht geladen werden.',
        onRetry: () => ref.invalidate(leagueSeasonFixturesProvider(leagueId)),
      ),
      data: (fixtures) {
        final groups = _computeGroups(fixtures);
        if (groups.isEmpty) {
          return const Center(
              child: Text('Noch keine Gruppentabelle verfügbar.'));
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(leagueSeasonFixturesProvider(leagueId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            children: [
              for (final g in groups) ...[
                _GroupHeader(label: g.label),
                const _TableHeader(),
                for (final r in g.rows) _TableRowTile(row: r),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
      child: Text(label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold, color: scheme.primary)),
    );
  }
}

class _Group {
  const _Group(this.label, this.rows);
  final String label;
  final List<StandingRow> rows;
}

class _Tally {
  _Tally(this.team);
  final TeamRef team;
  int played = 0, won = 0, draw = 0, lost = 0, gf = 0, ga = 0;
  int get points => won * 3 + draw;
  int get diff => gf - ga;
}

/// Bildet aus dem Gruppen-Spielplan die Vierergruppen (Teams, die
/// gegeneinander spielen) und berechnet je Gruppe die Tabelle. Gruppen
/// werden nach erstem Anstoß sortiert und A, B, C … benannt (best effort,
/// da OpenLigaDB keine Gruppen-Buchstaben liefert).
List<_Group> _computeGroups(List<Fixture> fixtures) {
  final groupFixtures = [
    for (final f in fixtures)
      if (f.roundName.toLowerCase().contains('gruppe')) f
  ];
  if (groupFixtures.isEmpty) return const [];

  final adj = <String, Set<String>>{};
  final teams = <String, TeamRef>{};
  for (final f in groupFixtures) {
    teams[f.home.id] = f.home;
    teams[f.away.id] = f.away;
    adj.putIfAbsent(f.home.id, () => {}).add(f.away.id);
    adj.putIfAbsent(f.away.id, () => {}).add(f.home.id);
  }

  // Zusammenhangskomponenten = Gruppen.
  final visited = <String>{};
  final comps = <List<String>>[];
  for (final id in adj.keys) {
    if (visited.contains(id)) continue;
    final comp = <String>[];
    final stack = <String>[id];
    visited.add(id);
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      comp.add(c);
      for (final n in adj[c] ?? const <String>{}) {
        if (visited.add(n)) stack.add(n);
      }
    }
    comps.add(comp);
  }

  final computed = <({List<StandingRow> rows, DateTime earliest})>[];
  for (final comp in comps) {
    final set = comp.toSet();
    final tallies = {for (final id in comp) id: _Tally(teams[id]!)};
    DateTime? earliest;
    for (final f in groupFixtures) {
      if (!set.contains(f.home.id) || !set.contains(f.away.id)) continue;
      if (earliest == null || f.kickoff.isBefore(earliest)) earliest = f.kickoff;
      if (f.status == FixtureStatus.finished &&
          f.homeScore != null &&
          f.awayScore != null) {
        final h = tallies[f.home.id]!;
        final a = tallies[f.away.id]!;
        h.played++;
        a.played++;
        h.gf += f.homeScore!;
        h.ga += f.awayScore!;
        a.gf += f.awayScore!;
        a.ga += f.homeScore!;
        if (f.homeScore! > f.awayScore!) {
          h.won++;
          a.lost++;
        } else if (f.homeScore! < f.awayScore!) {
          a.won++;
          h.lost++;
        } else {
          h.draw++;
          a.draw++;
        }
      }
    }
    final sorted = tallies.values.toList()
      ..sort((x, y) {
        final p = y.points - x.points;
        if (p != 0) return p;
        final d = y.diff - x.diff;
        if (d != 0) return d;
        final g = y.gf - x.gf;
        if (g != 0) return g;
        return x.team.name.compareTo(y.team.name);
      });
    final rows = [
      for (var i = 0; i < sorted.length; i++)
        StandingRow(
          rank: i + 1,
          team: sorted[i].team,
          points: sorted[i].points,
          played: sorted[i].played,
          won: sorted[i].won,
          draw: sorted[i].draw,
          lost: sorted[i].lost,
          goalsFor: sorted[i].gf,
          goalsAgainst: sorted[i].ga,
        ),
    ];
    computed
        .add((rows: rows, earliest: earliest ?? DateTime.fromMillisecondsSinceEpoch(0)));
  }

  computed.sort((a, b) => a.earliest.compareTo(b.earliest));
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  return [
    for (var i = 0; i < computed.length; i++)
      _Group(i < letters.length ? 'Gruppe ${letters[i]}' : 'Gruppe ${i + 1}',
          computed[i].rows),
  ];
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('#', style: style)),
          const SizedBox(width: 8),
          Expanded(child: Text('Team', style: style)),
          SizedBox(width: 30, child: Text('Sp', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 40, child: Text('Diff', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 34, child: Text('Pkt', style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _TableRowTile extends StatelessWidget {
  const _TableRowTile({required this.row});
  final StandingRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = row.goalDiff;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${row.rank}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          TeamBadge(team: row.team),
          const SizedBox(width: 8),
          Expanded(
            child: Text(row.team.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 30,
            child: Text('${row.played}',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          SizedBox(
            width: 40,
            child: Text(diff > 0 ? '+$diff' : '$diff',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          SizedBox(
            width: 34,
            child: Text('${row.points}',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Spieltage
// ---------------------------------------------------------------------
class _MatchdaysTab extends ConsumerStatefulWidget {
  const _MatchdaysTab({required this.leagueId});
  final String leagueId;

  @override
  ConsumerState<_MatchdaysTab> createState() => _MatchdaysTabState();
}

class _MatchdaysTabState extends ConsumerState<_MatchdaysTab> {
  int? _round;

  @override
  Widget build(BuildContext context) {
    final fixturesAsync = ref.watch(leagueSeasonFixturesProvider(widget.leagueId));

    return fixturesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Retry(
        message: 'Spieltage konnten nicht geladen werden.',
        onRetry: () =>
            ref.invalidate(leagueSeasonFixturesProvider(widget.leagueId)),
      ),
      data: (fixtures) {
        if (fixtures.isEmpty) {
          return const Center(
              child: Text('Noch kein Spielplan veröffentlicht.'));
        }
        // Nach Runde gruppieren.
        final byRound = <int, List<Fixture>>{};
        final names = <int, String>{};
        for (final f in fixtures) {
          byRound.putIfAbsent(f.round, () => []).add(f);
          names[f.round] = f.roundName;
        }
        final rounds = byRound.keys.toList()..sort();
        // Aktuellen Spieltag bestimmen: erster mit noch nicht beendetem Spiel.
        final current = rounds.firstWhere(
          (r) => byRound[r]!.any((f) => f.status != FixtureStatus.finished),
          orElse: () => rounds.last,
        );
        final round = _round ?? current;
        final idx = rounds.indexOf(round).clamp(0, rounds.length - 1);
        final activeRound = rounds[idx];
        final games = [...byRound[activeRound]!]
          ..sort((a, b) => a.kickoff.compareTo(b.kickoff));

        return Column(
          children: [
            _RoundSelector(
              name: names[activeRound] ?? 'Spieltag $activeRound',
              canPrev: idx > 0,
              canNext: idx < rounds.length - 1,
              onPrev: () => setState(() => _round = rounds[idx - 1]),
              onNext: () => setState(() => _round = rounds[idx + 1]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                children: [for (final f in games) _FixtureRow(fixture: f)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoundSelector extends StatelessWidget {
  const _RoundSelector({
    required this.name,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  final String name;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: canPrev ? onPrev : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(name,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: canNext ? onNext : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _FixtureRow extends StatelessWidget {
  const _FixtureRow({required this.fixture});
  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
    final live = f.status == FixtureStatus.live;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Row(children: [
                TeamBadge(team: f.home),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f.home.shortName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            SizedBox(
              width: 64,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.hasScore)
                    Text('${f.homeScore}:${f.awayScore}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                live ? MatchUpColors.red : scheme.onSurface))
                  else
                    Text(DateFormat('dd.MM.\nHH:mm').format(f.kickoff.toLocal()),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  if (live)
                    const Text('● LIVE',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: MatchUpColors.red)),
                ],
              ),
            ),
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(
                  child: Text(f.away.shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end),
                ),
                const SizedBox(width: 8),
                TeamBadge(team: f.away),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Erneut laden')),
        ],
      ),
    );
  }
}
