import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../logic/tip_weeks.dart';
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

/// Navigation zwischen Spielwochen (Do–Mi) in Multi-Wettbewerb-Runden;
/// gemeinsam genutzt von Tippen-Feed und Tipp-Tabelle. Zeigt „Woche N ·
/// Datumsspanne" und blättert über [selectedWeekProvider].
class WeekSelector extends ConsumerWidget {
  const WeekSelector({super.key, required this.weeks, required this.index});

  final List<TipWeek> weeks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    TipWeek? week;
    for (final w in weeks) {
      if (w.index == index) {
        week = w;
        break;
      }
    }
    final first = weeks.isNotEmpty ? weeks.first.index : index;
    final last = weeks.isNotEmpty ? weeks.last.index : index;
    final label = week == null ? 'Woche $index' : _label(week);

    void go(int to) => ref.read(selectedWeekProvider.notifier).state = to;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: index > first ? () => go(index - 1) : null,
          ),
          SizedBox(
            width: 200,
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: index < last ? () => go(index + 1) : null,
          ),
        ],
      ),
    );
  }

  /// „Woche N · 15.–21. Sep" — Datumsspanne aus erstem/letztem Spieltag der Woche.
  String _label(TipWeek week) {
    final df = DateFormat('d. MMM', 'de_DE');
    final first = week.fixtures.first.kickoff.toLocal();
    final last = week.fixtures.last.kickoff.toLocal();
    final String range;
    if (first.year == last.year &&
        first.month == last.month &&
        first.day == last.day) {
      range = df.format(first);
    } else if (first.year == last.year && first.month == last.month) {
      // Gleicher Monat: „15.–21. Sep"
      range = '${first.day}.–${df.format(last)}';
    } else {
      range = '${df.format(first)} – ${df.format(last)}';
    }
    return 'Woche ${week.index} · $range';
  }
}
