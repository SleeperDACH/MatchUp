import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../core/models/top_scorer.dart';
import '../features/news/providers.dart';
import '../features/news/ui/news_tile.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'match_detail_screen.dart';
import 'theme.dart';
import 'widgets/league_logo.dart';

/// Liga-Übersicht mit Tabs: Spieltage, Tabelle, Torjäger und liga-spezifische
/// News. Aufgerufen über die Liga-Buttons im Live-Tab.
class LeagueOverviewScreen extends StatelessWidget {
  const LeagueOverviewScreen({super.key, required this.league});

  final LeagueInfo league;

  @override
  Widget build(BuildContext context) {
    // Der DFB-Pokal ist ein K.-o.-Wettbewerb ohne Ligatabelle.
    final showTable = league.id != 'dfb_pokal';
    final tabs = <Tab>[
      const Tab(text: 'Spieltage'),
      if (showTable) const Tab(text: 'Tabelle'),
      const Tab(text: 'Torjäger'),
      const Tab(text: 'News'),
    ];
    final views = <Widget>[
      _MatchdaysTab(leagueId: league.id),
      if (showTable) _TableTab(leagueId: league.id),
      _TopScorersTab(leagueId: league.id),
      _NewsTab(leagueId: league.id),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LeagueLogo(leagueId: league.id, size: 26),
              const SizedBox(width: 8),
              Flexible(
                child: Text(league.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          bottom: TabBar(tabs: tabs),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

/// Anzeigename einer Runde: bei Liga-Wettbewerben „N. Spieltag", beim
/// DFB-Pokal der Rundenname (1. Runde … Finale).
String roundDisplayName(String leagueId, int round) {
  if (leagueId == 'dfb_pokal') {
    return switch (round) {
      1 => '1. Runde',
      2 => '2. Runde',
      3 => 'Achtelfinale',
      4 => 'Viertelfinale',
      5 => 'Halbfinale',
      6 => 'Finale',
      _ => 'Runde $round',
    };
  }
  return '$round. Spieltag';
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
        for (final f in fixtures) {
          byRound.putIfAbsent(f.round, () => []).add(f);
        }
        // Beim DFB-Pokal alle sechs Runden zeigen (auch noch nicht ausgeloste),
        // sonst die tatsächlich vorhandenen Spieltage.
        final isCup = widget.leagueId == 'dfb_pokal';
        final rounds = isCup
            ? const [1, 2, 3, 4, 5, 6]
            : (byRound.keys.toList()..sort());
        // Aktuelle Runde: erste mit noch nicht beendetem Spiel; beim Pokal gilt
        // eine noch leere (nicht ausgeloste) Runde als „aktuell/nächste".
        final current = rounds.firstWhere(
          (r) {
            final games = byRound[r];
            if (games == null || games.isEmpty) return isCup;
            return games.any((f) => f.status != FixtureStatus.finished);
          },
          orElse: () => rounds.last,
        );
        final round = _round ?? current;
        final idx = rounds.indexOf(round).clamp(0, rounds.length - 1);
        final activeRound = rounds[idx];
        final games = [...?byRound[activeRound]]
          ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
        // Spieltag nach Datum gruppieren, darin je Anstoßzeit ein eigenes
        // „Fenster": So landet der Samstags-Block gemeinsam in einer Karte und
        // ein allein angesetztes Topspiel (z. B. Sa. 18:30) automatisch in
        // einer eigenen.
        final sections = _groupByDate(games);

        return Column(
          children: [
            _RoundSelector(
              name: roundDisplayName(widget.leagueId, activeRound),
              canPrev: idx > 0,
              canNext: idx < rounds.length - 1,
              onPrev: () => setState(() => _round = rounds[idx - 1]),
              onNext: () => setState(() => _round = rounds[idx + 1]),
            ),
            Expanded(
              child: games.isEmpty
                  ? const _EmptyRound()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                        for (final section in sections) ...[
                          _DateHeader(date: section.date),
                          for (final slot in section.slots)
                            _SlotWindow(slot: slot),
                        ],
                      ],
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

// --- Gruppierung eines Spieltags nach Datum und Anstoßzeit ---------------

/// Ein Kalendertag eines Spieltags mit seinen Anstoßzeit-Fenstern.
class _DateSection {
  _DateSection(this.date);
  final DateTime date; // lokale Mitternacht
  final List<_Slot> slots = [];
}

/// Ein Anstoßzeit-Fenster (alle Spiele derselben Uhrzeit).
class _Slot {
  _Slot(this.time);
  final DateTime time; // lokale Anstoßzeit
  final List<Fixture> games = [];
}

/// Gruppiert die (nach Anstoß sortierten) Spiele eines Spieltags nach
/// Kalendertag und darin nach Anstoßzeit. Reihenfolge bleibt chronologisch.
List<_DateSection> _groupByDate(List<Fixture> games) {
  final sections = <_DateSection>[];
  for (final f in games) {
    final lt = f.kickoff.toLocal();
    final day = DateTime(lt.year, lt.month, lt.day);
    _DateSection section;
    if (sections.isNotEmpty && sections.last.date == day) {
      section = sections.last;
    } else {
      section = _DateSection(day);
      sections.add(section);
    }
    final slotTime = DateTime(lt.year, lt.month, lt.day, lt.hour, lt.minute);
    if (section.slots.isNotEmpty && section.slots.last.time == slotTime) {
      section.slots.last.games.add(f);
    } else {
      section.slots.add(_Slot(slotTime)..games.add(f));
    }
  }
  return sections;
}

/// Datums-Überschrift zwischen den Fenstern (z. B. „Samstag, 26.07.").
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = DateFormat('EEEE, dd.MM.', 'de_DE').format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        label[0].toUpperCase() + label.substring(1),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Ein Anstoßzeit-Fenster als eigene Karte: kleine Uhrzeit-Kopfzeile und
/// darunter die Spiele dieser Uhrzeit. Ein allein angesetztes Spiel (z. B.
/// Topspiel) steht damit automatisch in einer eigenen Karte.
class _SlotWindow extends StatelessWidget {
  const _SlotWindow({required this.slot});
  final _Slot slot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = slot.games.any((f) => f.status == FixtureStatus.live);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: scheme.onSurface),
                const SizedBox(width: 5),
                Text(DateFormat('HH:mm').format(slot.time),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.bold)),
                if (live) ...[
                  const Spacer(),
                  const Text('● LIVE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: MatchUpColors.red)),
                ],
              ],
            ),
            const SizedBox(height: 2),
            for (var i = 0; i < slot.games.length; i++) ...[
              if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
              _SlotGame(fixture: slot.games[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Eine Spielzeile innerhalb eines Zeitfensters (ohne eigene Karte/Datum —
/// die Uhrzeit steht im Fenster-Kopf).
class _SlotGame extends StatelessWidget {
  const _SlotGame({required this.fixture});
  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
    final live = f.status == FixtureStatus.live;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MatchDetailScreen(fixtureId: f.id))),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            // Name außen, Logo innen (zur Mitte) → Wappen fluchten.
            child: Row(children: [
              Expanded(
                child: Text(f.home.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              TeamBadge(team: f.home),
            ]),
          ),
          SizedBox(
            width: 46,
            child: f.hasScore
                ? Text('${f.homeScore}:${f.awayScore}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: live ? MatchUpColors.red : scheme.onSurface))
                : Text('–',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            // Logo innen (zur Mitte), Name außen → Wappen fluchten.
            child: Row(children: [
              TeamBadge(team: f.away),
              const SizedBox(width: 8),
              Expanded(
                child: Text(f.away.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end),
              ),
            ]),
          ),
        ],
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Torjäger
// ---------------------------------------------------------------------
class _TopScorersTab extends ConsumerWidget {
  const _TopScorersTab({required this.leagueId});
  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leagueTopScorersProvider(leagueId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Retry(
        message: 'Torjäger konnten nicht geladen werden.',
        onRetry: () => ref.invalidate(leagueTopScorersProvider(leagueId)),
      ),
      data: (res) {
        if (res.scorers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch keine Torjäger — die Saison hat noch nicht begonnen.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(leagueTopScorersProvider(leagueId)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            itemCount: res.scorers.length + (res.current ? 0 : 1),
            itemBuilder: (context, i) {
              if (!res.current && i == 0) {
                return _SeasonFallbackBanner(seasonName: res.seasonName);
              }
              final s = res.scorers[i - (res.current ? 0 : 1)];
              return _ScorerTile(scorer: s);
            },
          ),
        );
      },
    );
  }
}

/// Deutlich sichtbarer Hinweis, dass die Liste aus der letzten Saison stammt
/// (die neue hat noch nicht begonnen), damit die Tore nicht als aktuell
/// missverstanden werden.
class _SeasonFallbackBanner extends StatelessWidget {
  const _SeasonFallbackBanner({this.seasonName});
  final String? seasonName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = seasonName != null
        ? 'Torjäger der Saison $seasonName'
        : 'Torjäger der letzten Saison';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Die neue Saison hat noch nicht begonnen.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScorerTile extends StatelessWidget {
  const _ScorerTile({required this.scorer});
  final TopScorer scorer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final img = scorer.playerImg;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${scorer.position}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.surfaceContainerHighest,
            backgroundImage: img != null ? NetworkImage(img) : null,
            child: img == null
                ? Icon(Icons.person, size: 18, color: scheme.onSurfaceVariant)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scorer.playerName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (scorer.teamName != null)
                  Text(scorer.teamName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${scorer.goals}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: scheme.primary)),
          const SizedBox(width: 2),
          Text('Tore',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// News (liga-spezifisch)
// ---------------------------------------------------------------------
class _NewsTab extends ConsumerWidget {
  const _NewsTab({required this.leagueId});
  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leagueNewsProvider(leagueId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Retry(
        message: 'News konnten nicht geladen werden.',
        onRetry: () => ref.invalidate(leagueNewsProvider(leagueId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
              child: Text('Aktuell keine News für diesen Wettbewerb.'));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(leagueNewsProvider(leagueId)),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => NewsTile(item: items[i]),
          ),
        );
      },
    );
  }
}

/// Platzhalter für eine Pokalrunde, die noch nicht ausgelost ist.
class _EmptyRound extends StatelessWidget {
  const _EmptyRound();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Diese Runde ist noch nicht ausgelost.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
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
