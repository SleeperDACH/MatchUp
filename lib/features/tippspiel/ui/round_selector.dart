import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../providers.dart';

/// Navigation zwischen Runden („Gruppenphase 1" … „Finale", Spieltage);
/// gemeinsam genutzt von Tippen-Tab und Tipp-Tabelle.
class RoundSelector extends ConsumerWidget {
  const RoundSelector({super.key, required this.league, required this.round});

  final LeagueInfo league;
  final int round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Offizielle Rundenliste: begrenzt die Navigation und zeigt bei
    // Turnieren auch K.o.-Runden, deren Paarungen noch nicht feststehen.
    final rounds = ref.watch(availableRoundsProvider).valueOrNull;

    String label = '${league.roundLabel} $round';
    int? previous = round > 1 ? round - 1 : null;
    int? next = round + 1;
    if (rounds != null && rounds.isNotEmpty) {
      final index = rounds.indexWhere((r) => r.number == round);
      if (index >= 0) {
        if (rounds[index].name.isNotEmpty) label = rounds[index].name;
        previous = index > 0 ? rounds[index - 1].number : null;
        next = index < rounds.length - 1 ? rounds[index + 1].number : null;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: previous == null
                ? null
                : () =>
                    ref.read(selectedRoundProvider.notifier).state = previous,
          ),
          SizedBox(
            width: 180,
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: next == null
                ? null
                : () => ref.read(selectedRoundProvider.notifier).state = next,
          ),
        ],
      ),
    );
  }
}
