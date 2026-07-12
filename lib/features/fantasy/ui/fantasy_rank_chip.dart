import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logic/round_robin.dart';
import '../../../core/ui/rank_chip.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// Zeigt meinen aktuellen H2H-Tabellenplatz einer Fantasy-Liga als Chip
/// („Platz x/n"). Rendert nichts, solange Daten fehlen, die Liga < 2 Manager
/// hat oder noch kein Spieltag gewertet wurde.
class FantasyRankChip extends ConsumerWidget {
  const FantasyRankChip({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (league.draftStatus != DraftStatus.done) return const SizedBox.shrink();
    final myId = ref.watch(currentUserProvider)?.id;
    final managers =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull;
    final seasonStats = ref.watch(seasonStatsProvider).valueOrNull;
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull;

    if (myId == null ||
        managers == null ||
        managers.length < 2 ||
        pool == null ||
        roster == null ||
        seasonStats == null) {
      return const SizedBox.shrink();
    }

    final playerById = {for (final p in pool) p.id: p};
    final ids = managers.map((m) => m.userId).toList()
      ..sort((a, b) {
        final pa = managers.firstWhere((m) => m.userId == a).draftPosition ??
            1 << 30;
        final pb = managers.firstWhere((m) => m.userId == b).draftPosition ??
            1 << 30;
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
          lineups: lineups ?? const <FantasyLineup>[],
          scoring: league.scoring,
          rosterConfig: league.roster,
        )
    };
    final standings = h2hStandings(ids, totalsByRound);
    if (standings.every((r) => r.played == 0)) return const SizedBox.shrink();

    final idx = standings.indexWhere((r) => r.managerId == myId);
    if (idx < 0) return const SizedBox.shrink();
    return RankChip(rank: idx + 1, total: managers.length);
  }
}
