import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'matchday_stepper.dart';
import 'player_flag.dart';

/// „Mein Team": der gedraftete Kader eines Managers, gruppiert nach
/// Position, mit den Punkten des gewählten Spieltags und der automatisch
/// gebildeten besten Startelf.
class MyTeamScreen extends ConsumerStatefulWidget {
  const MyTeamScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<MyTeamScreen> createState() => _MyTeamScreenState();
}

class _MyTeamScreenState extends ConsumerState<MyTeamScreen> {
  int? _round;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final current = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? current ?? 34;

    final picks = ref.watch(draftPicksProvider(league.id)).valueOrNull ??
        const <DraftPick>[];
    final poolAsync = ref.watch(playerPoolProvider);
    final statsAsync = ref.watch(roundStatsProvider(round));
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Mein Team')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final playerById = {for (final p in pool) p.id: p};
          final myPlayers = [
            for (final pk in picks)
              if (pk.managerId == myId && playerById[pk.playerId] != null)
                playerById[pk.playerId]!
          ];
          final stats = statsAsync.valueOrNull ?? const {};
          final points = {
            for (final p in myPlayers)
              p: scorePlayer(stats[p.id] ?? const PlayerMatchStats(),
                  p.position, league.scoring)
          };
          final lineup = bestEleven(points, league.roster);

          return Column(
            children: [
              MatchdayStepper(
                  round: round, onChanged: (r) => setState(() => _round = r)),
              _TotalHeader(
                  total: lineup.total, loading: statsAsync.isLoading),
              Expanded(
                child: myPlayers.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Noch kein Kader — der Draft muss erst laufen.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final pos in PlayerPosition.values)
                            ..._positionSection(
                                pos, myPlayers, points, stats, lineup),
                          const _ScoringNote(),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _positionSection(
    PlayerPosition pos,
    List<FantasyPlayer> players,
    Map<FantasyPlayer, int> points,
    Map<String, PlayerMatchStats> stats,
    Lineup lineup,
  ) {
    final inPos = players.where((p) => p.position == pos).toList()
      ..sort((a, b) => (points[b] ?? 0).compareTo(points[a] ?? 0));
    if (inPos.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(pos.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
      for (final p in inPos)
        _PlayerRow(
          player: p,
          points: points[p] ?? 0,
          stats: stats[p.id],
          isStarter: lineup.starterIds.contains(p.id),
        ),
    ];
  }
}

class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.total, required this.loading});

  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.primary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(loading ? '…' : '$total',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: scheme.primary)),
          Text('Punkte · beste Startelf',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.points,
    required this.stats,
    required this.isStarter,
  });

  final FantasyPlayer player;
  final int points;
  final PlayerMatchStats? stats;
  final bool isStarter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = <String>[
      if ((stats?.goals ?? 0) > 0) '${stats!.goals} Tor${stats!.goals > 1 ? 'e' : ''}',
      if (stats?.cleanSheet ?? false) 'Zu Null',
    ].join(' · ');

    return Opacity(
      opacity: isStarter ? 1 : 0.55,
      child: ListTile(
        dense: true,
        leading: PlayerFlag(code: player.nationality),
        title: Row(
          children: [
            Flexible(child: Text(player.name, overflow: TextOverflow.ellipsis)),
            if (!isStarter)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('Bank',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ),
          ],
        ),
        subtitle: Text(detail.isEmpty ? player.club : '${player.club} · $detail'),
        trailing: Text('$points',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isStarter ? scheme.primary : scheme.onSurfaceVariant)),
      ),
    );
  }
}

class _ScoringNote extends StatelessWidget {
  const _ScoringNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Wertung aus echten OpenLigaDB-Daten: Tore und Zu-Null. Assists, '
        'Karten und Einsatzminuten folgen mit einem vollständigen Stats-Feed.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
