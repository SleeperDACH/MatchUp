import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/match_detail.dart';
import '../core/models/models.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'theme.dart';
import 'widgets/pulsing_dot.dart';

/// Spiel-Detailansicht: Ergebnis (inkl. Halbzeit, Verlängerung, Elfmeter),
/// Torschützen und Spielort — aus dem kostenlosen OpenLigaDB-Feed.
class MatchDetailScreen extends ConsumerStatefulWidget {
  const MatchDetailScreen({super.key, required this.fixtureId});

  final String fixtureId;

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Auto-Aktualisierung nur, solange das Spiel läuft.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final d = ref.read(matchDetailProvider(widget.fixtureId)).valueOrNull;
      if (d?.status == FixtureStatus.live) {
        ref.invalidate(matchDetailProvider(widget.fixtureId));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(matchDetailProvider(widget.fixtureId));
    return Scaffold(
      appBar: AppBar(title: const Text('Spieldetails')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Spieldaten konnten nicht geladen werden.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(matchDetailProvider(widget.fixtureId)),
                  child: const Text('Erneut laden'),
                ),
              ],
            ),
          ),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(matchDetailProvider(widget.fixtureId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _Header(detail: d),
              const SizedBox(height: 12),
              _ResultLines(detail: d),
              if (d.stadium != null || d.city != null) ...[
                const SizedBox(height: 12),
                _Location(stadium: d.stadium, city: d.city),
              ],
              const SizedBox(height: 24),
              Text('Torschützen',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _Goals(detail: d),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = detail;
    final live = d.status == FixtureStatus.live;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _TeamColumn(team: d.home)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (d.hasScore)
                  Text('${d.homeScore}:${d.awayScore}',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: live ? MatchUpColors.red : scheme.onSurface))
                else
                  Column(
                    children: [
                      Text(DateFormat('HH:mm').format(d.kickoff.toLocal()),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(DateFormat('d. MMM', 'de_DE').format(d.kickoff.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                const SizedBox(height: 6),
                if (live)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      PulsingDot(size: 7),
                      SizedBox(width: 4),
                      Text('LIVE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: MatchUpColors.red)),
                    ],
                  )
                else
                  Text(
                      d.status == FixtureStatus.finished ? 'beendet' : 'Anstoß',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant)),
              ],
            ),
            Expanded(child: _TeamColumn(team: d.away)),
          ],
        ),
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({required this.team});
  final TeamRef team;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TeamBadge(team: team, size: 48),
        const SizedBox(height: 8),
        Text(team.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Halbzeit / nach Verlängerung / Elfmeterschießen, sofern vorhanden.
class _ResultLines extends StatelessWidget {
  const _ResultLines({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = <(String, (int, int))>[
      if (detail.halfTime != null) ('Halbzeit', detail.halfTime!),
      if (detail.afterExtraTime != null)
        ('nach Verlängerung', detail.afterExtraTime!),
      if (detail.penalties != null) ('Elfmeterschießen', detail.penalties!),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (label, (h, a)) in lines)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$label  $h:$a',
                style: Theme.of(context).textTheme.labelMedium),
          ),
      ],
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({this.stadium, this.city});
  final String? stadium;
  final String? city;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = [stadium, city].where((e) => e != null && e.isNotEmpty).join(' · ');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.place_outlined, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _Goals extends StatelessWidget {
  const _Goals({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (detail.goals.isEmpty) {
      final msg = detail.status == FixtureStatus.scheduled
          ? 'Das Spiel hat noch nicht begonnen.'
          : (detail.status == FixtureStatus.live
              ? 'Noch keine Tore.'
              : 'Keine Tordaten verfügbar.');
      return Text(msg,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant));
    }
    return Column(
      children: [for (final g in detail.goals) _GoalRow(goal: g)],
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});
  final MatchGoal goal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = <String>[
      if (goal.penalty) 'Elfmeter',
      if (goal.ownGoal) 'Eigentor',
    ];
    final label = Column(
      crossAxisAlignment:
          goal.forHomeTeam ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(goal.scorer,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: goal.forHomeTeam ? TextAlign.start : TextAlign.end),
        if (extras.isNotEmpty)
          Text(extras.join(' · '),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
      ],
    );
    final scoreBox = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${goal.scoreHome}:${goal.scoreAway}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
    );
    final minute = SizedBox(
      width: 34,
      child: Text(goal.minute != null ? "${goal.minute}'" : '',
          textAlign: goal.forHomeTeam ? TextAlign.left : TextAlign.right,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: scheme.primary)),
    );
    const ball = Icon(Icons.sports_soccer, size: 14);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: goal.forHomeTeam
            ? [
                minute,
                const SizedBox(width: 4),
                ball,
                const SizedBox(width: 6),
                Expanded(child: label),
                scoreBox,
                const Expanded(child: SizedBox()),
              ]
            : [
                const Expanded(child: SizedBox()),
                scoreBox,
                Expanded(child: label),
                const SizedBox(width: 6),
                ball,
                const SizedBox(width: 4),
                minute,
              ],
      ),
    );
  }
}
