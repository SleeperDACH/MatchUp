import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/matchup_schedule.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'matchday_stepper.dart';

/// Head-to-Head-Matchups: pro Spieltag 1-gegen-1-Paarungen plus die
/// Saison-Bilanztabelle (Siege-Niederlagen-Unentschieden). Der Spielplan
/// ist deterministisch aus der Manager-Reihenfolge (Round-Robin).
class MatchupsScreen extends ConsumerStatefulWidget {
  const MatchupsScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<MatchupsScreen> createState() => _MatchupsScreenState();
}

class _MatchupsScreenState extends ConsumerState<MatchupsScreen> {
  int? _round;

  /// Effektive Punkte aller Manager für einen Spieltag.
  Map<String, int> _totals(
    Map<String, PlayerMatchStats> stats,
    int round, {
    required List<FantasyManager> managers,
    required List<RosterEntry> roster,
    required Map<String, FantasyPlayer> playerById,
    required List<FantasyLineup> lineups,
  }) {
    final league = widget.league;
    final out = <String, int>{};
    for (final m in managers) {
      final players = [
        for (final r in roster)
          if (r.managerId == m.userId && playerById[r.playerId] != null)
            playerById[r.playerId]!
      ];
      final points = {
        for (final p in players)
          p: scorePlayer(
              stats[p.id] ?? const PlayerMatchStats(), p.position, league.scoring)
      };
      final manual = lineups
          .where((l) => l.round == round && l.managerId == m.userId)
          .map((l) => l.playerIds)
          .firstOrNull;
      out[m.userId] = effectiveLineup(points, league.roster, manual).total;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final current = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? current ?? 1;

    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final weekStats = ref.watch(roundStatsProvider(round)).valueOrNull ?? const {};
    final seasonStats = ref.watch(seasonStatsProvider).valueOrNull ?? const {};
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Matchups')),
      body: (managersAsync.isLoading || poolAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final managers = managersAsync.requireValue;
              final pool = poolAsync.requireValue;
              final playerById = {for (final p in pool) p.id: p};
              final nameOf = {for (final m in managers) m.userId: m.username};

              // Stabile Reihenfolge: Draft-Position, dann User-ID.
              final ids = managers.map((m) => m.userId).toList()
                ..sort((a, b) {
                  final ma = managers.firstWhere((m) => m.userId == a);
                  final mb = managers.firstWhere((m) => m.userId == b);
                  final pa = ma.draftPosition ?? 1 << 30;
                  final pb = mb.draftPosition ?? 1 << 30;
                  return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
                });

              if (ids.length < 2) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Head-to-Head braucht mindestens zwei Manager.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final weekTotals = _totals(weekStats, round,
                  managers: managers,
                  roster: roster,
                  playerById: playerById,
                  lineups: lineups);
              final pairings = roundPairings(ids, round);
              final played = current != null && round <= current;

              // Bilanz über alle gespielten Spieltage.
              final totalsByRound = <int, Map<String, int>>{
                for (final entry in seasonStats.entries)
                  entry.key: _totals(entry.value, entry.key,
                      managers: managers,
                      roster: roster,
                      playerById: playerById,
                      lineups: lineups)
              };
              final standings = h2hStandings(ids, totalsByRound);

              return ListView(
                children: [
                  MatchdayStepper(
                      round: round,
                      onChanged: (r) => setState(() => _round = r)),
                  if (ref.watch(roundStatsProvider(round)).isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  for (final m in pairings)
                    _MatchupCard(
                      homeName: nameOf[m.home] ?? '?',
                      awayName: m.isBye ? null : (nameOf[m.away] ?? '?'),
                      homePoints: weekTotals[m.home] ?? 0,
                      awayPoints: m.isBye ? 0 : (weekTotals[m.away] ?? 0),
                      played: played,
                      homeMe: m.home == myId,
                      awayMe: m.away == myId,
                    ),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('Bilanz (S-N-U)',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (standings.every((r) => r.played == 0))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        seasonStats.isEmpty
                            ? 'Noch keine gewerteten Spieltage (Stats werden '
                                'serverseitig gespiegelt).'
                            : 'Noch keine entschiedenen Matchups.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    )
                  else
                    for (final (i, r) in standings.indexed)
                      _StandingRow(
                        rank: i + 1,
                        name: nameOf[r.managerId] ?? '?',
                        record: r,
                        me: r.managerId == myId,
                      ),
                  const SizedBox(height: 16),
                ],
              );
            }),
    );
  }
}

class _MatchupCard extends StatelessWidget {
  const _MatchupCard({
    required this.homeName,
    required this.awayName,
    required this.homePoints,
    required this.awayPoints,
    required this.played,
    required this.homeMe,
    required this.awayMe,
  });

  final String homeName;
  final String? awayName; // null = Bye
  final int homePoints;
  final int awayPoints;
  final bool played;
  final bool homeMe;
  final bool awayMe;

  @override
  Widget build(BuildContext context) {
    if (awayName == null) {
      return Card(
        child: ListTile(
          title: Text(homeName,
              style: homeMe ? const TextStyle(fontWeight: FontWeight.bold) : null),
          trailing: Text('spielfrei',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    final homeWin = played && homePoints > awayPoints;
    final awayWin = played && awayPoints > homePoints;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
                child: _side(context, homeName, homeMe, homeWin,
                    align: CrossAxisAlignment.start)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                played ? '$homePoints : $awayPoints' : 'vs',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
            Expanded(
                child: _side(context, awayName!, awayMe, awayWin,
                    align: CrossAxisAlignment.end)),
          ],
        ),
      ),
    );
  }

  Widget _side(BuildContext context, String name, bool me, bool win,
      {required CrossAxisAlignment align}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          name,
          textAlign: align == CrossAxisAlignment.start
              ? TextAlign.start
              : TextAlign.end,
          style: TextStyle(
            fontWeight: me || win ? FontWeight.bold : FontWeight.normal,
            color: win ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        if (win)
          Text('Sieg',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
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
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: rank == 1
            ? scheme.primary.withValues(alpha: 0.25)
            : scheme.surfaceContainerHighest,
        child: Text('$rank', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(name,
          style: me ? const TextStyle(fontWeight: FontWeight.bold) : null),
      subtitle: Text('${record.pointsFor}:${record.pointsAgainst} Pkt.'),
      trailing: Text(
        '${record.wins}-${record.losses}-${record.ties}',
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold),
      ),
    );
  }
}
