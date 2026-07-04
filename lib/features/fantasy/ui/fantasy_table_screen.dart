import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'matchday_stepper.dart';

/// Eigenständiger Screen (mit AppBar) — dünne Hülle um [FantasyTableBody].
class FantasyTableScreen extends StatelessWidget {
  const FantasyTableScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liga-Tabelle')),
      body: FantasyTableBody(league: league),
    );
  }
}

/// Liga-Tabelle: Punkte je Manager an einem Spieltag (beste Startelf),
/// absteigend sortiert. Body ohne Scaffold, damit er als Tab einsetzbar ist.
class FantasyTableBody extends ConsumerStatefulWidget {
  const FantasyTableBody({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<FantasyTableBody> createState() => _FantasyTableBodyState();
}

class _FantasyTableBodyState extends ConsumerState<FantasyTableBody> {
  int? _round;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final current = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? current ?? 34;

    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final statsAsync = ref.watch(roundStatsProvider(round));
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final myId = ref.watch(currentUserProvider)?.id;

    return (managersAsync.isLoading || poolAsync.isLoading)
        ? const Center(child: CircularProgressIndicator())
        : Builder(builder: (context) {
              final managers = managersAsync.requireValue;
              final pool = poolAsync.requireValue;
              final playerById = {for (final p in pool) p.id: p};
              final stats = statsAsync.valueOrNull ?? const {};

              final rows = <({String name, bool me, int total})>[];
              for (final m in managers) {
                final players = [
                  for (final r in roster)
                    if (r.managerId == m.userId &&
                        playerById[r.playerId] != null)
                      playerById[r.playerId]!
                ];
                final points = {
                  for (final p in players)
                    p: scorePlayer(stats[p.id] ?? const PlayerMatchStats(),
                        p.position, league.scoring)
                };
                final manual = lineups
                    .where((l) => l.round == round && l.managerId == m.userId)
                    .map((l) => l.playerIds)
                    .firstOrNull;
                rows.add((
                  name: m.username,
                  me: m.userId == myId,
                  total: effectiveLineup(points, league.roster, manual).total,
                ));
              }
              rows.sort((a, b) => b.total.compareTo(a.total));

              return Column(
                children: [
                  MatchdayStepper(
                      round: round,
                      onChanged: (r) => setState(() => _round = r)),
                  if (statsAsync.isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final (i, r) in rows.indexed)
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: i == 0
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.25)
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                              ),
                              title: Text(r.name,
                                  style: r.me
                                      ? const TextStyle(
                                          fontWeight: FontWeight.bold)
                                      : null),
                              trailing: Text('${r.total} Pkt.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Punkte = gewählte Startelf (sonst automatisch die '
                            'beste Elf). Wertung aus OpenLigaDB (Tore, Zu-Null).',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            });
  }
}
