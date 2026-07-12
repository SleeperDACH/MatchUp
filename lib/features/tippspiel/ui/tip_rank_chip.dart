import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/odds/frozen_odds.dart';
import '../../../core/ui/rank_chip.dart';
import '../../auth/providers.dart';
import '../logic/round_table.dart';
import '../models/tip_round.dart';
import '../providers.dart';

/// Zeigt meinen aktuellen Punkte-Tabellenplatz einer Tipprunde als Chip
/// („Platz x/n"). Rendert nichts, solange Daten fehlen, die Runde < 2
/// Mitglieder hat oder noch keine Punkte vergeben wurden.
class TipRankChip extends ConsumerWidget {
  const TipRankChip({super.key, required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final members = ref.watch(roundMembersProvider(round.id)).valueOrNull;
    final tips = ref.watch(allRoundTipsProvider(round.id)).valueOrNull;
    final fixtures =
        ref.watch(leagueSeasonFixturesProvider(round.leagueId)).valueOrNull;
    final frozenOdds = ref.watch(frozenOddsProvider).valueOrNull ??
        const <String, FrozenOdds>{};

    if (myId == null ||
        members == null ||
        members.length < 2 ||
        tips == null ||
        fixtures == null) {
      return const SizedBox.shrink();
    }

    final totals = totalPointsByMember(
      members: members,
      tips: tips,
      fixtures: fixtures,
      rules: round.scoring,
      frozenOdds: frozenOdds,
    );
    // Solange niemand Punkte hat, ist der „Platz" nicht aussagekräftig.
    if (totals.values.every((p) => p == 0)) return const SizedBox.shrink();

    final ranks = ranksByPoints(members, totals);
    final myRank = ranks[myId];
    if (myRank == null) return const SizedBox.shrink();
    return RankChip(rank: myRank, total: members.length);
  }
}
