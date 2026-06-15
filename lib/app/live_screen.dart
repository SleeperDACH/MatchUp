import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'theme.dart';

/// Live-Tab: laufende, als Nächstes anstehende und zuletzt gespielte
/// Begegnungen des aktiven Wettbewerbs auf einen Blick.
class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = ref.watch(selectedLeagueProvider);
    final fixturesAsync = ref.watch(seasonFixturesProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Live'),
            Text(league.name,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: fixturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Retry(
          message: 'Spiele konnten nicht geladen werden.',
          onRetry: () => ref.invalidate(seasonFixturesProvider),
        ),
        data: (fixtures) {
          final live = [
            for (final f in fixtures)
              if (f.status == FixtureStatus.live) f
          ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
          final upcoming = [
            for (final f in fixtures)
              if (f.status == FixtureStatus.scheduled) f
          ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
          final recent = [
            for (final f in fixtures)
              if (f.status == FixtureStatus.finished) f
          ]..sort((a, b) => b.kickoff.compareTo(a.kickoff));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(seasonFixturesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (live.isEmpty && upcoming.isEmpty && recent.isEmpty)
                  const _Empty('Aktuell sind keine Spiele verfügbar.'),
                if (live.isNotEmpty) ...[
                  const _SectionHeader('Live jetzt', accent: true),
                  for (final f in live) _FixtureTile(fixture: f),
                  const SizedBox(height: 16),
                ],
                if (upcoming.isNotEmpty) ...[
                  const _SectionHeader('Als Nächstes'),
                  for (final f in upcoming.take(12)) _FixtureTile(fixture: f),
                  const SizedBox(height: 16),
                ],
                if (recent.isNotEmpty) ...[
                  const _SectionHeader('Zuletzt'),
                  for (final f in recent.take(8)) _FixtureTile(fixture: f),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.accent = false});

  final String title;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          if (accent) ...[
            const SizedBox(
              width: 8,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: MatchUpColors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final live = fixture.status == FixtureStatus.live;
    final finished = fixture.status == FixtureStatus.finished;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _TeamSide(team: fixture.home),
            ),
            _CenterInfo(fixture: fixture, live: live, finished: finished),
            Expanded(
              child: _TeamSide(team: fixture.away, alignEnd: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamSide extends StatelessWidget {
  const _TeamSide({required this.team, this.alignEnd = false});

  final TeamRef team;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final badge = TeamBadge(team: team);
    final label = Flexible(
      child: Text(
        team.shortName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
    final children = alignEnd
        ? [label, const SizedBox(width: 8), badge]
        : [badge, const SizedBox(width: 8), label];
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: children,
    );
  }
}

class _CenterInfo extends StatelessWidget {
  const _CenterInfo({
    required this.fixture,
    required this.live,
    required this.finished,
  });

  final Fixture fixture;
  final bool live;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fixture.hasScore)
            Text(
              '${fixture.homeScore}:${fixture.awayScore}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: live ? MatchUpColors.red : scheme.onSurface,
              ),
            )
          else
            Text(
              DateFormat('EEE HH:mm', 'de_DE').format(fixture.kickoff.toLocal()),
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 2),
          if (live)
            const Text('● LIVE',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: MatchUpColors.red))
          else if (finished)
            Text('beendet',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant))
          else
            Text(DateFormat('d. MMM', 'de_DE').format(fixture.kickoff.toLocal()),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(Icons.sports_soccer,
              size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Erneut laden')),
        ],
      ),
    );
  }
}
