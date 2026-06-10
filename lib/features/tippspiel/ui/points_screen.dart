import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/tip_scoring.dart';
import '../providers.dart';

/// Punkteübersicht über die Saison: Gesamtpunkte und Aufschlüsselung pro
/// Runde. Im MVP nur die eigenen Punkte; mit Supabase wird daraus die
/// Tipprunden-Tabelle aller Mitspieler.
class PointsScreen extends ConsumerWidget {
  const PointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixtures = ref.watch(seasonFixturesProvider);
    final tips = ref.watch(tipsProvider);
    final rules = ref.watch(scoringRulesProvider);
    final league = ref.watch(selectedLeagueProvider);

    return fixtures.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Punkte konnten nicht geladen werden.\n$e',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(seasonFixturesProvider),
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      ),
      data: (list) {
        var total = 0;
        var tippedCount = 0;
        var exactCount = 0;
        final perRound = <int, int>{};

        for (final fixture in list) {
          final tip = tips[fixture.id];
          if (tip == null || !fixture.hasResult) continue;
          tippedCount++;
          final points = scoreTip(
            tipHome: tip.homeGoals,
            tipAway: tip.awayGoals,
            resultHome: fixture.homeScore!,
            resultAway: fixture.awayScore!,
            rules: rules,
          );
          if (points == rules.exact) exactCount++;
          total += points;
          perRound.update(fixture.round, (v) => v + points,
              ifAbsent: () => points);
        }

        final rounds = perRound.keys.toList()..sort();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(seasonFixturesProvider),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _SummaryCard(
                total: total,
                tippedCount: tippedCount,
                exactCount: exactCount,
              ),
              if (rounds.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Noch keine gewerteten Tipps.\nTippe Spiele auf dem Spieltag-Tab!',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final round in rounds.reversed)
                Card(
                  child: ListTile(
                    title: Text('${league.roundLabel} $round'),
                    trailing: Text(
                      '${perRound[round]} Pkt.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.tippedCount,
    required this.exactCount,
  });

  final int total;
  final int tippedCount;
  final int exactCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('$total',
                style: Theme.of(context)
                    .textTheme
                    .displayMedium
                    ?.copyWith(color: scheme.primary)),
            const Text('Punkte gesamt'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Stat(label: 'Gewertete Tipps', value: '$tippedCount'),
                _Stat(label: 'Volltreffer', value: '$exactCount'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
