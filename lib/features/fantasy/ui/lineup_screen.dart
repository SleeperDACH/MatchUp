import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'matchday_stepper.dart';
import 'player_flag.dart';

/// Manuelle Aufstellung: Startelf je Spieltag selbst wählen (feste Formation
/// aus der Kader-Konfiguration, z. B. 1/4/4/2). Vor Anstoß änderbar, danach
/// gesperrt. Ohne gespeicherte Aufstellung zählt die automatische beste Elf.
class LineupScreen extends ConsumerStatefulWidget {
  const LineupScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<LineupScreen> createState() => _LineupScreenState();
}

class _LineupScreenState extends ConsumerState<LineupScreen> {
  int? _round;

  /// Vom Nutzer bearbeitete Auswahl; null = noch ungespeicherte Saat
  /// (bestehende Aufstellung bzw. automatische beste Elf) wird gezeigt.
  Set<String>? _selected;
  bool _saving = false;

  RosterConfig get _roster => widget.league.roster;

  int _slotFor(PlayerPosition pos) => switch (pos) {
        PlayerPosition.gk => _roster.gk,
        PlayerPosition.def => _roster.def,
        PlayerPosition.mid => _roster.mid,
        PlayerPosition.fwd => _roster.fwd,
      };

  void _toggle(FantasyPlayer p, Set<String> current) {
    final next = {...current};
    if (next.contains(p.id)) {
      next.remove(p.id);
    } else {
      final inPos = next.where((id) => _posOfSelected(id) == p.position).length;
      if (inPos >= _slotFor(p.position)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${p.position.label}: schon ${_slotFor(p.position)} aufgestellt')));
        return;
      }
      next.add(p.id);
    }
    setState(() => _selected = next);
  }

  // Position eines aktuell ausgewählten Spielers (aus dem Pool-Cache).
  PlayerPosition? Function(String) _posOfSelected = (_) => null;

  Future<void> _save(List<String> ids) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .setLineup(widget.league.id, _round!, ids);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aufstellung gespeichert')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final current = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? current ?? 34;

    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final statsAsync = ref.watch(roundStatsProvider(round));
    final deadline = ref.watch(roundDeadlineProvider(round)).valueOrNull;
    final myId = ref.watch(currentUserProvider)?.id;

    final locked = deadline != null && !DateTime.now().isBefore(deadline);

    return Scaffold(
      appBar: AppBar(title: const Text('Aufstellung')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final playerById = {for (final p in pool) p.id: p};
          _posOfSelected = (id) => playerById[id]?.position;
          final myPlayers = [
            for (final r in roster)
              if (r.managerId == myId && playerById[r.playerId] != null)
                playerById[r.playerId]!
          ];
          final stats = statsAsync.valueOrNull ?? const {};
          final points = {
            for (final p in myPlayers)
              p: scorePlayer(stats[p.id] ?? const PlayerMatchStats(),
                  p.position, league.scoring)
          };

          // Saat: gespeicherte Aufstellung dieses Spieltags, sonst beste Elf.
          final existing = lineups
              .where((l) => l.round == round && l.managerId == myId)
              .map((l) => l.playerIds)
              .firstOrNull;
          final seed = existing != null && existing.isNotEmpty
              ? {
                  // nur noch im Kader befindliche Spieler übernehmen
                  for (final id in existing)
                    if (playerById.containsKey(id) &&
                        myPlayers.any((p) => p.id == id))
                      id
                }
              : bestEleven(points, _roster).starterIds;
          final selection = _selected ?? seed;

          final total = chosenLineup(points, selection).total;

          return Column(
            children: [
              MatchdayStepper(
                round: round,
                onChanged: (r) => setState(() {
                  _round = r;
                  _selected = null; // neue Runde -> neu saaten
                }),
              ),
              _Header(
                total: total,
                count: selection.length,
                starters: _roster.starters,
                locked: locked,
                deadline: deadline,
                loadingStats: statsAsync.isLoading,
              ),
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
                            ..._section(pos, myPlayers, points, selection,
                                stats, locked),
                          const SizedBox(height: 80),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: locked
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving
                  ? null
                  : () => _save((_selected ?? _lastSeed).toList()),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Speichern'),
            ),
    );
  }

  // Merkt sich die zuletzt gezeigte Saat, damit „Speichern" ohne Bearbeiten
  // die automatische Elf festschreibt.
  Set<String> _lastSeed = const {};

  List<Widget> _section(
    PlayerPosition pos,
    List<FantasyPlayer> players,
    Map<FantasyPlayer, int> points,
    Set<String> selection,
    Map<String, PlayerMatchStats> stats,
    bool locked,
  ) {
    _lastSeed = selection;
    final inPos = players.where((p) => p.position == pos).toList()
      ..sort((a, b) => (points[b] ?? 0).compareTo(points[a] ?? 0));
    if (inPos.isEmpty) return const [];
    final picked = inPos.where((p) => selection.contains(p.id)).length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(pos.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text('$picked/${_slotFor(pos)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
      for (final p in inPos)
        CheckboxListTile(
          value: selection.contains(p.id),
          onChanged: locked ? null : (_) => _toggle(p, selection),
          secondary: PlayerFlag(code: p.nationality),
          title: Text(p.name),
          subtitle: Text(p.club),
          controlAffinity: ListTileControlAffinity.trailing,
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.count,
    required this.starters,
    required this.locked,
    required this.deadline,
    required this.loadingStats,
  });

  final int total;
  final int count;
  final int starters;
  final bool locked;
  final DateTime? deadline;
  final bool loadingStats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = locked
        ? 'Gesperrt — der Spieltag hat begonnen.'
        : deadline == null
            ? 'Noch kein Anstoß-Termin — jederzeit änderbar.'
            : 'Änderbar bis ${_fmt(deadline!)} (Anstoß).';
    return Container(
      width: double.infinity,
      color: scheme.primary.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        children: [
          Text(loadingStats ? '… Pkt.' : '$total Pkt.',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: scheme.primary)),
          Text('Startelf $count/$starters',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(locked ? Icons.lock_outline : Icons.schedule,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(hint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    final l = d.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mi = l.minute.toString().padLeft(2, '0');
    return '$dd.$mm. $hh:$mi';
  }
}
