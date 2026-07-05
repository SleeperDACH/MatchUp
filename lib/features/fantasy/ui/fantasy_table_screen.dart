import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/matchup_schedule.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// Eigenständiger Screen (mit AppBar) — dünne Hülle um [FantasyTableBody].
class FantasyTableScreen extends StatelessWidget {
  const FantasyTableScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liga-Tabelle')),
      body: FantasyTableBody(league: league),
    );
  }
}

/// Liga-Tabelle nach **Head-to-Head-Bilanz**: pro Spieltag ein 1-gegen-1
/// (effektive Startelf), gewertet als Sieg / Unentschieden / Niederlage.
/// Sortiert nach Siegen, dann Punktedifferenz. Body ohne Scaffold, damit er
/// als Tab einsetzbar ist.
class FantasyTableBody extends ConsumerWidget {
  const FantasyTableBody({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final seasonStatsAsync = ref.watch(seasonStatsProvider);
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final myId = ref.watch(currentUserProvider)?.id;

    if (managersAsync.isLoading || poolAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final managers = managersAsync.requireValue;
    final pool = poolAsync.requireValue;
    final playerById = {for (final p in pool) p.id: p};
    final nameOf = {for (final m in managers) m.userId: m.username};
    final seasonStats = seasonStatsAsync.valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};

    if (managers.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Die Tabelle braucht mindestens zwei Manager.',
              textAlign: TextAlign.center),
        ),
      );
    }

    // Stabile Reihenfolge (Draft-Position, dann User-ID) für den Round-Robin.
    final ids = managers.map((m) => m.userId).toList()
      ..sort((a, b) {
        final ma = managers.firstWhere((m) => m.userId == a);
        final mb = managers.firstWhere((m) => m.userId == b);
        final pa = ma.draftPosition ?? 1 << 30;
        final pb = mb.draftPosition ?? 1 << 30;
        return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
      });

    final totalsByRound = <int, Map<String, int>>{
      for (final entry in seasonStats.entries)
        entry.key: effectiveTotalsForRound(
          stats: entry.value,
          round: entry.key,
          managers: managers,
          roster: roster,
          playerById: playerById,
          lineups: lineups,
          scoring: league.scoring,
          rosterConfig: league.roster,
        )
    };
    final standings = h2hStandings(ids, totalsByRound);
    final nonePlayed = standings.every((r) => r.played == 0);

    return ListView(
      children: [
        if (seasonStatsAsync.isLoading)
          const LinearProgressIndicator(minHeight: 2),
        const _TableHeader(),
        if (nonePlayed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text(
              'Noch keine gewerteten Spieltage — die Bilanz startet bei 0.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        // Teilnehmer immer anzeigen (auch mit 0-0-0 vor dem ersten Spieltag).
        for (final (i, r) in standings.indexed)
          _RecordRow(
            rank: i + 1,
            name: nameOf[r.managerId] ?? '?',
            record: r,
            me: r.managerId == myId,
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Bilanz aus Head-to-Head je Spieltag (effektive Startelf). '
            'Sortiert nach Siegen, dann Punktedifferenz. S = Siege, '
            'U = Unentschieden, N = Niederlagen.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

const _wCol = 30.0;
const _wDiff = 52.0;

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget cell(String t) =>
        SizedBox(width: _wCol, child: Text(t, textAlign: TextAlign.center, style: style));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: style)),
          Expanded(child: Text('Team', style: style)),
          cell('S'),
          cell('U'),
          cell('N'),
          SizedBox(
              width: _wDiff,
              child: Text('Diff', textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.rank,
    required this.name,
    required this.record,
    required this.me,
  });

  final int rank;
  final String name;
  final H2HRecord record;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = record.pointsFor - record.pointsAgainst;
    Widget num(int v, Color color) => SizedBox(
          width: _wCol,
          child: Text('$v',
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        );
    return Container(
      color: me ? scheme.primary.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: rank == 1 ? scheme.primary : scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: me ? const TextStyle(fontWeight: FontWeight.bold) : null),
          ),
          num(record.wins, scheme.primary),
          num(record.ties, scheme.onSurfaceVariant),
          num(record.losses, scheme.error),
          SizedBox(
            width: _wDiff,
            child: Text(diff >= 0 ? '+$diff' : '$diff',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: diff > 0
                        ? scheme.primary
                        : diff < 0
                            ? scheme.error
                            : scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
