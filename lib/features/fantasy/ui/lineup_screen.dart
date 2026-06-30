import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'matchday_stepper.dart';
import 'player_flag.dart';

/// Aufstellung als Fußballfeld: Startelf je Spieltag visuell auf dem Platz
/// wählen. Oben Chips für gültige Formationen (flexibel, Min/Max je Position
/// aus der Kader-Konfiguration); Tippen auf eine Position öffnet die Liste der
/// verfügbaren Spieler **derselben Position** (ein Stürmer kann nicht in die
/// Abwehr). Vor Anstoß änderbar, danach gesperrt. Ohne gespeicherte
/// Aufstellung zählt die automatische beste Elf.
class LineupScreen extends ConsumerStatefulWidget {
  const LineupScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<LineupScreen> createState() => _LineupScreenState();
}

/// Reihenfolge auf dem Platz: Sturm oben, Torwart unten.
const _pitchOrder = [
  PlayerPosition.fwd,
  PlayerPosition.mid,
  PlayerPosition.def,
  PlayerPosition.gk,
];

class _LineupScreenState extends ConsumerState<LineupScreen> {
  int? _round;

  /// Aufstellung als feste Slot-Listen je Position (Länge = Formation),
  /// Einträge können leer (null) sein. null = noch ungespeicherte Saat zeigen.
  Map<PlayerPosition, List<String?>>? _slots;
  bool _saving = false;

  bool _valid = false;
  List<String> _lastIds = const [];

  RosterConfig get _roster => widget.league.roster;

  /// Alle aktuell aufgestellten Spieler-IDs (über alle Positionen).
  Set<String> _assignedIds(Map<PlayerPosition, List<String?>> slots) => {
        for (final list in slots.values)
          for (final id in list) ?id
      };

  /// Slots für eine Formation bauen; bevorzugt Spieler aus [prefer]
  /// (bestehende Auswahl / gespeicherte Elf), füllt sonst die punktbesten.
  Map<PlayerPosition, List<String?>> _buildSlots(
    (int, int, int) formation,
    Set<String> prefer,
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
  ) {
    final counts = {
      PlayerPosition.gk: _roster.gk,
      PlayerPosition.def: formation.$1,
      PlayerPosition.mid: formation.$2,
      PlayerPosition.fwd: formation.$3,
    };
    final res = <PlayerPosition, List<String?>>{};
    counts.forEach((pos, n) {
      final ordered = byPos[pos] ?? const <FantasyPlayer>[];
      final preferred = [for (final p in ordered) if (prefer.contains(p.id)) p.id];
      final rest = [for (final p in ordered) if (!prefer.contains(p.id)) p.id];
      final pick = [...preferred, ...rest].take(n).toList();
      res[pos] = [for (var i = 0; i < n; i++) i < pick.length ? pick[i] : null];
    });
    return res;
  }

  (int, int, int) _formationOf(Map<PlayerPosition, List<String?>> slots) => (
        slots[PlayerPosition.def]?.length ?? 0,
        slots[PlayerPosition.mid]?.length ?? 0,
        slots[PlayerPosition.fwd]?.length ?? 0,
      );

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
          final myPlayers = [
            for (final r in roster)
              if (r.managerId == myId && playerById[r.playerId] != null)
                playerById[r.playerId]!
          ];
          final stats =
              statsAsync.valueOrNull ?? const <String, PlayerMatchStats>{};
          final points = {
            for (final p in myPlayers)
              p: scorePlayer(stats[p.id] ?? const PlayerMatchStats(),
                  p.position, league.scoring)
          };
          // Spieler je Position, nach Punkten absteigend (für Auto-Fill/Listen).
          final byPos = <PlayerPosition, List<FantasyPlayer>>{};
          for (final p in myPlayers) {
            byPos.putIfAbsent(p.position, () => []).add(p);
          }
          for (final list in byPos.values) {
            list.sort((a, b) => (points[b] ?? 0).compareTo(points[a] ?? 0));
          }

          if (myPlayers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Noch kein Kader — der Draft muss erst laufen.',
                    textAlign: TextAlign.center),
              ),
            );
          }

          // Saat: gespeicherte Aufstellung dieses Spieltags, sonst beste Elf.
          final existing = lineups
              .where((l) => l.round == round && l.managerId == myId)
              .map((l) => l.playerIds)
              .firstOrNull;
          final seedIds = existing != null && existing.isNotEmpty
              ? {
                  for (final id in existing)
                    if (myPlayers.any((p) => p.id == id)) id
                }
              : bestEleven(points, _roster).starterIds;

          // Slots auflösen: Nutzer-Auswahl oder Saat (in gültiger Formation).
          final slots = _slots ?? _seedSlots(seedIds, byPos);

          final assigned = _assignedIds(slots);
          final total = [for (final id in assigned) points[playerById[id]] ?? 0]
              .fold<int>(0, (a, b) => a + b);
          final (d, m, f) = _formationOf(slots);
          final valid = _roster.isValidFormation(
              gkCount: slots[PlayerPosition.gk]?.whereType<String>().length ?? 0,
              defCount:
                  slots[PlayerPosition.def]?.whereType<String>().length ?? 0,
              midCount:
                  slots[PlayerPosition.mid]?.whereType<String>().length ?? 0,
              fwdCount:
                  slots[PlayerPosition.fwd]?.whereType<String>().length ?? 0);
          _valid = valid;
          _lastIds = assigned.toList();

          // Bank: Kaderspieler, die nicht aufgestellt sind.
          final bench = [
            for (final p in myPlayers)
              if (!assigned.contains(p.id)) p
          ]..sort((a, b) {
              final cmp = a.position.index.compareTo(b.position.index);
              return cmp != 0 ? cmp : (points[b] ?? 0).compareTo(points[a] ?? 0);
            });

          return Column(
            children: [
              MatchdayStepper(
                round: round,
                onChanged: (r) => setState(() {
                  _round = r;
                  _slots = null; // neue Runde -> neu saaten
                }),
              ),
              _Header(
                total: total,
                formation:
                    _roster.formationLabel(defCount: d, midCount: m, fwdCount: f),
                valid: valid,
                locked: locked,
                deadline: deadline,
                loadingStats: statsAsync.isLoading,
              ),
              if (!locked)
                _FormationChips(
                  roster: _roster,
                  byPos: byPos,
                  current: (d, m, f),
                  onSelected: (fm) => setState(
                      () => _slots = _buildSlots(fm, assigned, byPos)),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _Pitch(
                        slots: slots,
                        playerById: playerById,
                        points: points,
                        onTapSlot: locked
                            ? null
                            : (pos, i) =>
                                _openPicker(pos, i, slots, byPos, points, stats),
                        onDrop: locked
                            ? null
                            : (data, pos, i) => _applyDrop(slots, data, pos, i),
                      ),
                      _Bench(
                        bench: bench,
                        points: points,
                        onDropToBench:
                            locked ? null : (data) => _benchDrop(slots, data),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: poolAsync.hasValue && !locked
          ? FloatingActionButton.extended(
              backgroundColor: _valid ? null : Theme.of(context).disabledColor,
              onPressed: (_saving || !_valid) ? null : () => _save(_lastIds),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Speichern'),
            )
          : null,
    );
  }

  /// Saat-Slots aus einer Startelf-Menge; nimmt deren Formation, fällt bei
  /// ungültiger (z. B. degenerierter Kader) auf die erste machbare zurück.
  Map<PlayerPosition, List<String?>> _seedSlots(
    Set<String> seedIds,
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
  ) {
    int cnt(PlayerPosition pos) =>
        (byPos[pos] ?? const []).where((p) => seedIds.contains(p.id)).length;
    var formation =
        (cnt(PlayerPosition.def), cnt(PlayerPosition.mid), cnt(PlayerPosition.fwd));
    final isValid = _roster.isValidFormation(
        gkCount: _roster.gk,
        defCount: formation.$1,
        midCount: formation.$2,
        fwdCount: formation.$3);
    if (!isValid) {
      final feasible = _feasibleFormations(byPos);
      if (feasible.isNotEmpty) formation = feasible.first;
    }
    return _buildSlots(formation, seedIds, byPos);
  }

  /// Gültige Formationen, die der Kader auch besetzen kann.
  List<(int, int, int)> _feasibleFormations(
      Map<PlayerPosition, List<FantasyPlayer>> byPos) {
    int avail(PlayerPosition pos) => (byPos[pos] ?? const []).length;
    return [
      for (final fm in _roster.validFormations())
        if (fm.$1 <= avail(PlayerPosition.def) &&
            fm.$2 <= avail(PlayerPosition.mid) &&
            fm.$3 <= avail(PlayerPosition.fwd) &&
            _roster.gk <= avail(PlayerPosition.gk))
          fm
    ];
  }

  Future<void> _openPicker(
    PlayerPosition pos,
    int slotIndex,
    Map<PlayerPosition, List<String?>> slots,
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
    Map<FantasyPlayer, int> points,
    Map<String, PlayerMatchStats> stats,
  ) async {
    final samePosAssigned = slots[pos]!.whereType<String>().toSet();
    // Verfügbar: Spieler dieser Position, die nicht schon aufgestellt sind.
    final candidates = [
      for (final p in byPos[pos] ?? const <FantasyPlayer>[])
        if (!samePosAssigned.contains(p.id)) p
    ];
    final occupied = slots[pos]![slotIndex] != null;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PlayerPicker(
        position: pos,
        candidates: candidates,
        points: points,
        stats: stats,
        canClear: occupied,
      ),
    );
    if (picked == null) return;
    setState(() {
      final next = {
        for (final e in slots.entries) e.key: [...e.value]
      };
      next[pos]![slotIndex] = picked == _clearSentinel ? null : picked;
      _slots = next;
    });
  }

  Map<PlayerPosition, List<String?>> _copy(
          Map<PlayerPosition, List<String?>> s) =>
      {for (final e in s.entries) e.key: [...e.value]};

  /// Spieler per Drag & Drop auf einen Platz ziehen. Gleiche Position ist
  /// durch das DragTarget garantiert: vom Feld → Tausch der beiden Plätze,
  /// von der Bank → der bisherige Spieler rückt auf die Bank.
  void _applyDrop(
    Map<PlayerPosition, List<String?>> slots,
    _DragData data,
    PlayerPosition pos,
    int index,
  ) {
    final next = _copy(slots);
    final occupant = next[pos]![index];
    final from = data.from;
    if (from != null) next[from.$1]![from.$2] = occupant;
    next[pos]![index] = data.playerId;
    HapticFeedback.selectionClick();
    setState(() => _slots = next);
  }

  /// Einen aufgestellten Spieler per Drag auf die Bank setzen (Platz wird frei).
  void _benchDrop(Map<PlayerPosition, List<String?>> slots, _DragData data) {
    final from = data.from;
    if (from == null) return; // war schon Bank
    final next = _copy(slots);
    next[from.$1]![from.$2] = null;
    HapticFeedback.selectionClick();
    setState(() => _slots = next);
  }
}

const _clearSentinel = '__clear__';

/// Nutzdaten eines gezogenen Spielers: ID, Position und Herkunft
/// (Feld-Slot `from` = (Position, Index); `null` = von der Bank).
class _DragData {
  const _DragData({required this.playerId, required this.pos, this.from});
  final String playerId;
  final PlayerPosition pos;
  final (PlayerPosition, int)? from;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.formation,
    required this.valid,
    required this.locked,
    required this.deadline,
    required this.loadingStats,
  });

  final int total;
  final String formation;
  final bool valid;
  final bool locked;
  final DateTime? deadline;
  final bool loadingStats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = locked
        ? 'Gesperrt — der Spieltag hat begonnen.'
        : !valid
            ? 'Noch nicht vollständig — alle Positionen besetzen.'
            : deadline == null
                ? 'Jederzeit änderbar — noch kein Anstoß-Termin.'
                : 'Änderbar bis ${_fmt(deadline!)} (Anstoß).';
    final hintColor = !locked && !valid ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      color: scheme.primary.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Column(
        children: [
          Text(loadingStats ? '… Pkt.' : '$total Pkt.',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: scheme.primary)),
          Text('Formation $formation',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: valid ? scheme.onSurfaceVariant : scheme.error)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  locked
                      ? Icons.lock_outline
                      : !valid
                          ? Icons.warning_amber_rounded
                          : Icons.schedule,
                  size: 14,
                  color: hintColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(hint,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: hintColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}. ${two(l.hour)}:${two(l.minute)}';
  }
}

class _FormationChips extends StatelessWidget {
  const _FormationChips({
    required this.roster,
    required this.byPos,
    required this.current,
    required this.onSelected,
  });

  final RosterConfig roster;
  final Map<PlayerPosition, List<FantasyPlayer>> byPos;
  final (int, int, int) current;
  final ValueChanged<(int, int, int)> onSelected;

  @override
  Widget build(BuildContext context) {
    int avail(PlayerPosition pos) => (byPos[pos] ?? const []).length;
    final formations = [
      for (final fm in roster.validFormations())
        if (fm.$1 <= avail(PlayerPosition.def) &&
            fm.$2 <= avail(PlayerPosition.mid) &&
            fm.$3 <= avail(PlayerPosition.fwd))
          fm
    ];
    if (formations.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final fm in formations)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${fm.$1}-${fm.$2}-${fm.$3}'),
                selected: fm == current,
                onSelected: (_) => onSelected(fm),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pitch extends StatelessWidget {
  const _Pitch({
    required this.slots,
    required this.playerById,
    required this.points,
    required this.onTapSlot,
    required this.onDrop,
  });

  final Map<PlayerPosition, List<String?>> slots;
  final Map<String, FantasyPlayer> playerById;
  final Map<FantasyPlayer, int> points;
  final void Function(PlayerPosition pos, int index)? onTapSlot;
  final void Function(_DragData data, PlayerPosition pos, int index)? onDrop;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      height: 420,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
      ),
      child: CustomPaint(
        painter: _PitchLinesPainter(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            children: [
              for (final pos in _pitchOrder)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < (slots[pos]?.length ?? 0); i++)
                        _slotTarget(pos, i),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slotTarget(PlayerPosition pos, int i) {
    final player = playerById[slots[pos]![i]];
    final pts = player == null ? null : points[player];
    return DragTarget<_DragData>(
      onWillAcceptWithDetails: (d) =>
          onDrop != null && d.data.pos == pos && d.data.from != (pos, i),
      onAcceptWithDetails: (d) => onDrop!(d.data, pos, i),
      builder: (context, candidate, rejected) {
        final slot = _Slot(
          player: player,
          posLabel: pos.short,
          points: pts,
          highlight: candidate.isNotEmpty,
          onTap: onTapSlot == null ? null : () => onTapSlot!(pos, i),
        );
        if (player == null || onDrop == null) return slot;
        final data = _DragData(playerId: player.id, pos: pos, from: (pos, i));
        return LongPressDraggable<_DragData>(
          data: data,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(player: player),
          childWhenDragging: Opacity(opacity: 0.3, child: slot),
          child: slot,
        );
      },
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.player,
    required this.posLabel,
    required this.points,
    required this.onTap,
    this.highlight = false,
  });

  final FantasyPlayer? player;
  final String posLabel;
  final int? points;
  final VoidCallback? onTap;

  /// Hervorhebung, wenn ein passender Spieler über diesen Platz gezogen wird.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: highlight ? Colors.white.withValues(alpha: 0.18) : null,
          border: Border.all(
            color: highlight ? Colors.white : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p == null)
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white24,
                  border: Border.all(color: Colors.white54, width: 1.5),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 22),
              )
            else
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: PlayerFlag(code: p.nationality),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${points ?? 0}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                p == null ? 'frei' : _short(p.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            const SizedBox(height: 1),
            // Positions-Kennzeichnung unter jedem Spieler.
            Text(
              posLabel,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
}

/// Spieler-Avatar als Drag-Vorschau unter dem Finger.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.player});

  final FantasyPlayer player;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Transform.translate(
        offset: const Offset(-27, -27),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: PlayerFlag(code: player.nationality),
        ),
      ),
    );
  }
}

class _Bench extends StatelessWidget {
  const _Bench(
      {required this.bench, required this.points, required this.onDropToBench});

  final List<FantasyPlayer> bench;
  final Map<FantasyPlayer, int> points;

  /// Aufgestellten Spieler per Drag auf die Bank setzen (`null` = gesperrt).
  final void Function(_DragData data)? onDropToBench;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: DragTarget<_DragData>(
        onWillAcceptWithDetails: (d) =>
            onDropToBench != null && d.data.from != null,
        onAcceptWithDetails: (d) => onDropToBench!(d.data),
        builder: (context, candidate, rejected) {
          final hot = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: hot ? scheme.primary.withValues(alpha: 0.10) : null,
              border: Border.all(
                color: hot ? scheme.primary : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bank (${bench.length})',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                if (bench.isEmpty)
                  Text(
                      hot
                          ? 'Hier ablegen, um auf die Bank zu setzen.'
                          : 'Alle Spieler stehen in der Startelf.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in bench) _benchChip(p),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _benchChip(FantasyPlayer p) {
    final chip = Chip(
      avatar: PlayerFlag(code: p.nationality),
      label: Text('${p.position.short} · ${_short(p.name)} · ${points[p] ?? 0}'),
    );
    if (onDropToBench == null) return chip;
    final data = _DragData(playerId: p.id, pos: p.position);
    return LongPressDraggable<_DragData>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(player: p),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
}

/// Zeichnet die Linien einer Fußballfeld-Hälfte: Außenlinie, Mittelkreis
/// (oben, halb), Straf- und Torraum samt Elfmeterpunkt und Bogen (unten, beim
/// Torwart). Liegt hinter den Spieler-Slots.
class _PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;

    const inset = 8.0;
    final w = size.width;
    final h = size.height;
    final top = inset, bottom = h - inset;
    final cx = w / 2;

    // Außenlinie (oben = Mittellinie, unten = Torlinie).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(inset, top, w - inset, bottom),
          const Radius.circular(8)),
      line,
    );

    // Mittelkreis als unterer Halbbogen + Anstoßpunkt auf der Mittellinie.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, top), radius: w * 0.16),
      0,
      3.14159,
      false,
      line,
    );
    canvas.drawCircle(Offset(cx, top), 2.5, dot);

    // Strafraum unten (3 Seiten; Torlinie ist die Außenlinie).
    final paW = w * 0.58, paH = h * 0.20;
    void box(double bw, double bh) {
      canvas.drawPath(
        Path()
          ..moveTo(cx - bw / 2, bottom)
          ..lineTo(cx - bw / 2, bottom - bh)
          ..lineTo(cx + bw / 2, bottom - bh)
          ..lineTo(cx + bw / 2, bottom),
        line,
      );
    }

    box(paW, paH); // Strafraum
    box(w * 0.30, h * 0.09); // Torraum

    // Elfmeterpunkt + Strafraumbogen („D"): nur der Teil oberhalb der
    // Strafraumkante. Die Bogen-Enden treffen exakt auf die Kante — Winkel aus
    // dem Abstand Elfmeterpunkt→Kante und dem Radius berechnet.
    final penSpotY = bottom - paH * 0.62;
    canvas.drawCircle(Offset(cx, penSpotY), 2.5, dot);
    final arcR = w * 0.15;
    final boxTopOffset = penSpotY - (bottom - paH); // Abstand Punkt→Strafraumkante
    final a = math.asin((boxTopOffset / arcR).clamp(-1.0, 1.0));
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, penSpotY), radius: arcR),
      math.pi + a, // oben-links auf der Kante
      math.pi - 2 * a, // über den Scheitel bis oben-rechts auf der Kante
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bottom-Sheet: verfügbare Spieler einer Position auswählen (oder Slot leeren).
class _PlayerPicker extends StatelessWidget {
  const _PlayerPicker({
    required this.position,
    required this.candidates,
    required this.points,
    required this.stats,
    required this.canClear,
  });

  final PlayerPosition position;
  final List<FantasyPlayer> candidates;
  final Map<FantasyPlayer, int> points;
  final Map<String, PlayerMatchStats> stats;
  final bool canClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Text('${position.label} wählen',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (canClear)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(_clearSentinel),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Slot leeren'),
                    ),
                ],
              ),
            ),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Keine weiteren ${position.label}-Spieler im Kader.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, i) {
                    final p = candidates[i];
                    final s = stats[p.id];
                    final detail = <String>[
                      p.club,
                      if ((s?.goals ?? 0) > 0) '${s!.goals} Tor',
                      if (s?.cleanSheet ?? false) 'Zu Null',
                    ].join(' · ');
                    return ListTile(
                      leading: PlayerFlag(code: p.nationality),
                      title: Text(p.name),
                      subtitle: Text(detail),
                      trailing: Text('${points[p] ?? 0}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary)),
                      onTap: () => Navigator.of(context).pop(p.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
