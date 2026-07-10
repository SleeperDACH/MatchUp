import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logic/round_robin.dart';
import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
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
  // Hoher Startindex, damit man in beide Richtungen „endlos" wischen kann;
  // die tatsächliche Paarung ergibt sich per Modulo (zyklisches Karussell).
  static const _loopBase = 100000;

  int? _round;
  final _pageController = PageController(initialPage: _loopBase);
  int _bannerPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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
    final allFx =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const <Fixture>[];
    final myId = ref.watch(currentUserProvider)?.id;

    return (managersAsync.isLoading || poolAsync.isLoading)
        ? const Center(child: CircularProgressIndicator())
        : Builder(builder: (context) {
              final managers = managersAsync.requireValue;
              final pool = poolAsync.requireValue;
              final playerById = {for (final p in pool) p.id: p};
              final nameOf = {for (final m in managers) m.userId: m.display};

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

              // Live-/Beendet-Status des Spieltags aus den Fixtures.
              final roundFx = [
                for (final f in allFx)
                  if (f.round == round) f
              ];
              final live = roundIsLive(roundFx, DateTime.now());
              final started = live ||
                  (roundFx.isNotEmpty &&
                      roundFx.every((f) => f.status == FixtureStatus.finished));

              // Eigene Paarung zuerst (Platz 1), dann die übrigen — wischbar.
              final myPairing = myId == null
                  ? null
                  : pairings
                      .where((m) => m.home == myId || m.away == myId)
                      .firstOrNull;
              final ordered = <Matchup>[
                ?myPairing,
                for (final m in pairings)
                  if (myPairing == null || !identical(m, myPairing)) m,
              ];
              // Anzeige-Reihenfolge: bei der eigenen Paarung stehe ich links.
              (String, String?) sidesOf(Matchup p) {
                if (p.isBye) return (p.home, null);
                if (p.away == myId) return (p.away!, p.home);
                return (p.home, p.away);
              }

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
              // Saison-Kontext je Manager fürs Banner: „Platz X · S-N-U".
              final subOf = <String, String>{
                for (final (i, r) in standings.indexed)
                  r.managerId: 'P${i + 1} · ${r.wins}-${r.losses}-${r.ties}',
              };

              final page =
                  ordered.isEmpty ? 0 : _bannerPage.clamp(0, ordered.length - 1);

              return ListView(
                children: [
                  MatchdayStepper(
                    round: round,
                    onChanged: (r) {
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(_loopBase);
                      }
                      setState(() {
                        _round = r;
                        _bannerPage = 0;
                      });
                    },
                  ),
                  if (ref.watch(roundStatsProvider(round)).isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  // Wischbares Banner-Karussell: eigene Paarung auf Platz 1.
                  SizedBox(
                    height: 224,
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (i) => setState(() => _bannerPage =
                          ((i - _loopBase) % ordered.length + ordered.length) %
                              ordered.length),
                      // itemCount offen lassen -> zyklisch in beide Richtungen.
                      itemBuilder: (context, i) {
                        final logical =
                            ((i - _loopBase) % ordered.length + ordered.length) %
                                ordered.length;
                        final p = ordered[logical];
                        final (hId, aId) = sidesOf(p);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          child: MatchupBanner(
                            round: round,
                            homeName: nameOf[hId] ?? '?',
                            awayName: aId == null ? null : (nameOf[aId] ?? '?'),
                            homePoints: weekTotals[hId] ?? 0,
                            awayPoints: aId == null ? 0 : (weekTotals[aId] ?? 0),
                            homeMe: hId == myId,
                            awayMe: aId == myId,
                            live: live,
                            started: started,
                            mine: hId == myId || aId == myId,
                            homeSub: subOf[hId],
                            awaySub: aId == null ? null : subOf[aId],
                            onTap: aId == null
                                ? () {}
                                : () => showMatchupDetail(context,
                                    league: league,
                                    round: round,
                                    homeId: hId,
                                    homeName: nameOf[hId] ?? '?',
                                    awayId: aId,
                                    awayName: nameOf[aId] ?? '?'),
                          ),
                        );
                      },
                    ),
                  ),
                  if (ordered.length > 1)
                    _Dots(count: ordered.length, active: page),
                  const SizedBox(height: 8),
                  // Aufstellungen der aktuell gewischten Paarung.
                  if (ordered.isNotEmpty)
                    Builder(builder: (context) {
                      final p = ordered[page];
                      final (hId, aId) = sidesOf(p);
                      final home = computeSideData(
                          league: league,
                          round: round,
                          managerId: hId,
                          byId: playerById,
                          roster: roster,
                          lineups: lineups,
                          stats: weekStats);
                      final away = aId == null
                          ? null
                          : computeSideData(
                              league: league,
                              round: round,
                              managerId: aId,
                              byId: playerById,
                              roster: roster,
                              lineups: lineups,
                              stats: weekStats);
                      return MatchupLineups(
                        league: league,
                        home: home,
                        away: away,
                        homeId: hId,
                        awayId: aId,
                        homeName: nameOf[hId] ?? '?',
                        awayName: aId == null ? null : (nameOf[aId] ?? '?'),
                      );
                    }),
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

/// Seiten-Indikator (Punkte) unter dem Banner-Karussell.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == active
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
