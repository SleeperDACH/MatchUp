import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/rank_chip.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// Zeigt meinen aktuellen H2H-Tabellenplatz einer Fantasy-Liga als Chip
/// („Platz x/n"). Rendert nichts, solange nichts feststeht — die Bedingungen
/// dafür stehen in [myFantasyRankProvider], damit die Liga-Karte auf dem
/// Homescreen dieselbe Wertung benutzt und nicht eine zweite.
class FantasyRankChip extends ConsumerWidget {
  const FantasyRankChip({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platz = ref.watch(myFantasyRankProvider(league.id));
    if (platz == null) return const SizedBox.shrink();
    return RankChip(rank: platz.rank, total: platz.total);
  }
}
