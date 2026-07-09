import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../../../core/logic/round_robin.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'manager_profile_screen.dart';
import 'matchday_stepper.dart';
import 'matchup_detail_screen.dart';
import 'matchup_hero.dart';
import 'matchup_lineups.dart';

/// Eigenständiger Screen (mit AppBar) — dünne Hülle um [MatchupsBody].
class MatchupsScreen extends StatelessWidget {
  const MatchupsScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matchups')),
      body: MatchupsBody(league: league),
    );
  }
}

/// Head-to-Head-Matchups: pro Spieltag 1-gegen-1-Paarungen plus die
/// Saison-Bilanztabelle (Siege-Niederlagen-Unentschieden). Der Spielplan
/// ist deterministisch aus der Manager-Reihenfolge (Round-Robin).
/// Body ohne Scaffold, damit er als Tab einsetzbar ist.
class MatchupsBody extends ConsumerStatefulWidget {
  const MatchupsBody({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<MatchupsBody> createState() => _MatchupsBodyState();
}

class _MatchupsBodyState extends ConsumerState<MatchupsBody> {
  int? _round;

  /// Effektive Punkte aller Manager für einen Spieltag (geteilte Logik).
  Map<String, int> _totals(
    Map<String, PlayerMatchStats> stats,
    int round, {
    required List<FantasyManager> managers,
    required List<RosterEntry> roster,
    required Map<String, FantasyPlayer> playerById,
    required List<FantasyLineup> lineups,
  }) =>
      effectiveTotalsForRound(
        stats: stats,
        round: round,
        managers: managers,
        roster: roster,
        playerById: playerById,
        lineups: lineups,
        scoring: widget.league.scoring,
        rosterConfig: widget.league.roster,
      );

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

    return (managersAsync.isLoading || poolAsync.isLoading)
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

              // Eigene Paarung des Spieltags: sie wird oben groß herausgestellt
              // (Banner wie in der Übersicht + Aufstellungen), die restlichen
              // Paarungen bleiben darunter als Karten.
              final myPairing = myId == null
                  ? null
                  : pairings
                      .where((m) => m.home == myId || m.away == myId)
                      .firstOrNull;
              final myOppId = myPairing == null || myPairing.isBye
                  ? null
                  : (myPairing.home == myId ? myPairing.away : myPairing.home);
              final myHome = myPairing == null
                  ? null
                  : computeSideData(
                      league: league,
                      round: round,
                      managerId: myId!,
                      byId: playerById,
                      roster: roster,
                      lineups: lineups,
                      stats: weekStats);
              final myAway = myOppId == null
                  ? null
                  : computeSideData(
                      league: league,
                      round: round,
                      managerId: myOppId,
                      byId: playerById,
                      roster: roster,
                      lineups: lineups,
                      stats: weekStats);

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
                  // Eigene Paarung: Banner (wie Übersicht) + Aufstellungen.
                  if (myPairing != null && myHome != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: MatchupHero(league: league, round: round),
                    ),
                    MatchupLineups(
                      league: league,
                      home: myHome,
                      away: myAway,
                      homeId: myId!,
                      awayId: myOppId,
                      homeName: nameOf[myId] ?? 'Du',
                      awayName:
                          myOppId == null ? null : (nameOf[myOppId] ?? '?'),
                    ),
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text('Weitere Paarungen',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ],
                  for (final m in pairings)
                    if (myPairing == null ||
                        (m.home != myId && m.away != myId))
                      _MatchupCard(
                        homeName: nameOf[m.home] ?? '?',
                        awayName: m.isBye ? null : (nameOf[m.away] ?? '?'),
                        homeId: m.home,
                        awayId: m.isBye ? null : m.away,
                        homePoints: weekTotals[m.home] ?? 0,
                        awayPoints: m.isBye ? 0 : (weekTotals[m.away] ?? 0),
                        played: played,
                        homeMe: m.home == myId,
                        awayMe: m.away == myId,
                        onOpen: (id, name) => showManagerProfile(context,
                            league: widget.league,
                            managerId: id,
                            managerName: name),
                        onOpenMatchup: m.isBye
                            ? null
                            : () => showMatchupDetail(context,
                                league: widget.league,
                                round: round,
                                homeId: m.home,
                                homeName: nameOf[m.home] ?? '?',
                                awayId: m.away,
                                awayName: nameOf[m.away] ?? '?'),
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
                        onTap: () => showManagerProfile(context,
                            league: widget.league,
                            managerId: r.managerId,
                            managerName: nameOf[r.managerId] ?? '?'),
                      ),
                  const SizedBox(height: 16),
                ],
              );
            });
  }
}

class _MatchupCard extends StatelessWidget {
  const _MatchupCard({
    required this.homeName,
    required this.awayName,
    required this.homeId,
    required this.awayId,
    required this.homePoints,
    required this.awayPoints,
    required this.played,
    required this.homeMe,
    required this.awayMe,
    required this.onOpen,
    this.onOpenMatchup,
  });

  final String homeName;
  final String? awayName; // null = Bye
  final String homeId;
  final String? awayId;
  final int homePoints;
  final int awayPoints;
  final bool played;
  final bool homeMe;
  final bool awayMe;
  final void Function(String id, String name) onOpen;
  final VoidCallback? onOpenMatchup;

  @override
  Widget build(BuildContext context) {
    if (awayName == null) {
      return Card(
        child: ListTile(
          onTap: () => onOpen(homeId, homeName),
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
                child: _side(context, homeId, homeName, homeMe, homeWin,
                    align: CrossAxisAlignment.start)),
            InkWell(
              onTap: onOpenMatchup,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      played ? '$homePoints : $awayPoints' : 'vs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    if (onOpenMatchup != null)
                      Icon(Icons.unfold_more,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.6)),
                  ],
                ),
              ),
            ),
            Expanded(
                child: _side(context, awayId!, awayName!, awayMe, awayWin,
                    align: CrossAxisAlignment.end)),
          ],
        ),
      ),
    );
  }

  Widget _side(BuildContext context, String id, String name, bool me, bool win,
      {required CrossAxisAlignment align}) {
    return InkWell(
      onTap: () => onOpen(id, name),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            name,
            textAlign: align == CrossAxisAlignment.start
                ? TextAlign.start
                : TextAlign.end,
            style: TextStyle(
              fontWeight: me || win ? FontWeight.bold : FontWeight.normal,
              decoration: TextDecoration.underline,
              decorationColor:
                  Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
              color: win ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          if (win)
            Text('Sieg',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.name,
    required this.record,
    required this.me,
    required this.onTap,
  });

  final int rank;
  final String name;
  final H2HRecord record;
  final bool me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      onTap: onTap,
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
