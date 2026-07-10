import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../data/draft_repository.dart';
import '../logic/draft_order.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'pitch_painter.dart';

/// Live-Draft-Raum: Snake-Reihenfolge, Pick-Timer (kurz = Live, lang =
/// Slow), Auto-Pick bei Ablauf und Picks in Echtzeit. Die Reihenfolge
/// und der Auto-Pick werden serverseitig erzwungen; hier laufen Anzeige,
/// Countdown und das Auslösen abgelaufener Picks.
class DraftRoomScreen extends ConsumerStatefulWidget {
  const DraftRoomScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<DraftRoomScreen> createState() => _DraftRoomScreenState();
}

class _DraftRoomScreenState extends ConsumerState<DraftRoomScreen> {
  Timer? _ticker;
  bool _autopickInFlight = false;
  late final DraftRepository _repo;

  String get _leagueId => widget.league.id;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(draftRepositoryProvider);
    // Anwesend im Raum → manueller Modus (hebt einen früheren Auto-Modus auf).
    unawaited(_repo.setAutoPick(_leagueId, false));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Raum verlassen → Auto-Modus, bis der Manager wieder beitritt.
    unawaited(_repo.setAutoPick(_leagueId, true));
    super.dispose();
  }

  void _onTick() {
    final league = ref.read(draftLeagueProvider(_leagueId)).valueOrNull;
    // Jede Sekunde prüfen: der Server pickt automatisch, wenn der Timer
    // abgelaufen ist ODER der Manager am Zug abwesend (Auto-Modus) ist.
    if (league != null &&
        league.draftStatus == DraftStatus.drafting &&
        !_autopickInFlight) {
      _autopickInFlight = true;
      _repo
          .autopickIfExpired(_leagueId)
          .whenComplete(() => _autopickInFlight = false);
    }
    if (mounted) setState(() {}); // Countdown aktualisieren
  }

  Future<void> _pick(FantasyPlayer player) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${player.name} draften?'),
        content: Text('${player.position.label} · ${player.club}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Draften'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(draftRepositoryProvider).makePick(_leagueId, player.id);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg.contains('nicht am Zug')
            ? 'Du bist gerade nicht am Zug.'
            : (msg.contains('bereits im Kader') ||
                    msg.contains('bereits gedraftet'))
                ? 'Der Spieler ist schon vergeben.'
                : 'Pick fehlgeschlagen: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagueAsync = ref.watch(draftLeagueProvider(_leagueId));
    final league = leagueAsync.valueOrNull ?? widget.league;
    final managersAsync = ref.watch(fantasyManagersProvider(_leagueId));
    final picksAsync = ref.watch(draftPicksProvider(_leagueId));
    final poolAsync = ref.watch(playerPoolProvider);
    final rosterAsync = ref.watch(leagueRosterProvider(_leagueId));
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;

    if (managersAsync.isLoading || poolAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final managers = [...managersAsync.requireValue]
      ..sort((a, b) => (a.draftPosition ?? 99).compareTo(b.draftPosition ?? 99));
    final pool = poolAsync.requireValue;
    final picks = picksAsync.valueOrNull ?? const <DraftPick>[];

    final playerById = {for (final p in pool) p.id: p};
    final nameById = {for (final m in managers) m.userId: m.display};
    final pickedIds = {for (final p in picks) p.playerId};

    // Eigener Kader (inkl. in Dynasty behaltener Spieler) nach Position — für
    // die Feld-Übersicht. Live über den Roster-Stream, füllt sich beim Draften.
    final roster = rosterAsync.valueOrNull ?? const <RosterEntry>[];
    final mySquad = <PlayerPosition, List<FantasyPlayer>>{};
    for (final r in roster) {
      if (r.managerId != myId) continue;
      final p = playerById[r.playerId];
      if (p != null) mySquad.putIfAbsent(p.position, () => []).add(p);
    }
    final mySquadSize = mySquad.values.fold<int>(0, (a, l) => a + l.length);

    // Dynasty: Haupt-Draft = etablierte Spieler, U20-Draft = U20 +
    // Auslands-Neuzugänge. Liga-Modus: ganzer Pool.
    bool inPhasePool(FantasyPlayer p) {
      if (league.mode != FantasyMode.dynasty) return true;
      final rookie = p.isRookieFor(league.season);
      return league.draftPhase == DraftPhase.u20 ? rookie : !rookie;
    }

    final available = pool
        .where((p) => !pickedIds.contains(p.id) && inPhasePool(p))
        .toList();
    final phasePicks =
        picks.where((p) => p.phase == league.draftPhase).toList();

    // Eigene Draft-Queue (Wunschliste, nach Rang).
    final queueIds =
        ref.watch(draftQueueProvider(_leagueId)).valueOrNull ?? const <String>[];
    final queueSet = queueIds.toSet();
    final queuePlayers = [
      for (final id in queueIds)
        if (playerById[id] != null) playerById[id]!
    ];
    void toggleQueue(String id) {
      final list = [...queueIds];
      list.contains(id) ? list.remove(id) : list.add(id);
      unawaited(_repo.setQueue(_leagueId, list));
    }

    final cur = currentManager(managers, league.picksMade);
    final myTurn = league.draftStatus == DraftStatus.drafting &&
        cur != null &&
        cur.userId == myId;
    final total = managers.length * league.roundsThisPhase;
    final round =
        managers.isEmpty ? 1 : league.picksMade ~/ managers.length + 1;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(league.name),
          // Feste Vier-Tab-Leiste: alle auf einen Blick, kein Scrollen.
          bottom: TabBar(
            labelPadding: EdgeInsets.zero,
            tabs: [
              const Tab(
                  icon: Icon(Icons.groups_2_outlined, size: 20),
                  text: 'Spieler'),
              Tab(
                  icon: const Icon(Icons.bookmark_outline, size: 20),
                  text: 'Queue (${queuePlayers.length})'),
              Tab(
                  icon: const Icon(Icons.shield_outlined, size: 20),
                  text: 'Team ($mySquadSize)'),
              const Tab(
                  icon: Icon(Icons.grid_view_outlined, size: 20),
                  text: 'Board'),
            ],
          ),
        ),
        body: Column(
          children: [
            _StatusBanner(
              league: league,
              current: cur,
              myTurn: myTurn,
              total: total,
              round: round,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AvailableTab(
                    players: available,
                    canPick: myTurn,
                    onPick: _pick,
                    queued: queueSet,
                    onToggleQueue: toggleQueue,
                    clubIcons: clubIcons,
                  ),
                  _QueueTab(
                    players: queuePlayers,
                    canPick: myTurn,
                    onPick: _pick,
                    onRemove: toggleQueue,
                    onReorder: (ids) => unawaited(_repo.setQueue(_leagueId, ids)),
                  ),
                  _MyTeamTab(
                      byPos: mySquad,
                      roster: league.roster,
                      clubIcons: clubIcons),
                  _BoardTab(
                    picks: phasePicks,
                    playerById: playerById,
                    nameById: nameById,
                    managers: managers,
                    currentId: cur?.userId,
                    myId: myId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.league,
    required this.current,
    required this.myTurn,
    required this.total,
    required this.round,
  });

  final FantasyLeague league;
  final FantasyManager? current;
  final bool myTurn;
  final int total;
  final int round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (league.draftStatus == DraftStatus.done) {
      return _bar(context, scheme.primary.withValues(alpha: 0.15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Draft abgeschlossen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ));
    }
    if (league.draftStatus == DraftStatus.setup) {
      return _bar(context, scheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('Warten auf den Draft-Start durch den Admin',
                    textAlign: TextAlign.center),
              ),
            ],
          ));
    }

    final remaining = league.currentPickDeadline == null
        ? Duration.zero
        : league.currentPickDeadline!.difference(DateTime.now());
    final secs = remaining.inSeconds.clamp(0, 1 << 31);
    final clock =
        '${(secs ~/ 60)}:${(secs % 60).toString().padLeft(2, '0')}';

    final timerColor = secs <= 10 ? scheme.error : scheme.primary;
    return _bar(
      context,
      myTurn
          ? scheme.primary.withValues(alpha: 0.16)
          : scheme.surfaceContainerHigh,
      child: Row(
        children: [
          // Prominente Timer-Pille (Restzeit für den aktuellen Pick).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: timerColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 16, color: timerColor),
                const SizedBox(width: 6),
                Text(clock,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: timerColor)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Wer ist dran + Phase/Runde/Pick — alles auf einen Blick.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(myTurn ? Icons.sports_soccer : Icons.arrow_right_alt,
                        size: 16,
                        color:
                            myTurn ? scheme.primary : scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        myTurn
                            ? 'Du bist dran!'
                            : 'Am Zug: ${current?.display ?? '—'}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: myTurn ? scheme.primary : null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${league.mode == FantasyMode.dynasty ? '${league.draftPhase.label} · ' : ''}Runde $round · Pick ${league.picksMade + 1}/$total',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, Color color, {required Widget child}) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: child,
    );
  }
}

class _AvailableTab extends StatefulWidget {
  const _AvailableTab({
    required this.players,
    required this.canPick,
    required this.onPick,
    required this.queued,
    required this.onToggleQueue,
    required this.clubIcons,
  });

  final List<FantasyPlayer> players;
  final bool canPick;
  final Future<void> Function(FantasyPlayer) onPick;
  final Set<String> queued;
  final ValueChanged<String> onToggleQueue;
  final Map<String, String?> clubIcons;

  @override
  State<_AvailableTab> createState() => _AvailableTabState();
}

class _AvailableTabState extends State<_AvailableTab> {
  String _query = '';
  PlayerPosition? _position;

  @override
  Widget build(BuildContext context) {
    var list = widget.players
        .where((p) => _position == null || p.position == _position)
        .where((p) =>
            _query.isEmpty ||
            p.name.toLowerCase().contains(_query.toLowerCase()) ||
            p.club.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Spieler oder Verein suchen',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _filterChip('Alle', _position == null,
                  () => setState(() => _position = null)),
              for (final pos in PlayerPosition.values)
                _filterChip(pos.label, _position == pos,
                    () => setState(() => _position = pos)),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Keine Spieler verfügbar.'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final inQueue = widget.queued.contains(p.id);
                    final scheme = Theme.of(context).colorScheme;
                    return ListTile(
                      leading: ClubBadge(
                          club: p.club, iconUrl: widget.clubIcons[p.club]),
                      title: Text(p.name),
                      subtitle: Text('${p.position.short} · ${p.club}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: inQueue
                                ? 'Aus Queue entfernen'
                                : 'Zur Queue hinzufügen',
                            icon: Icon(
                              inQueue
                                  ? Icons.bookmark_added
                                  : Icons.bookmark_add_outlined,
                              color: inQueue ? scheme.primary : null,
                            ),
                            onPressed: () => widget.onToggleQueue(p.id),
                          ),
                          if (widget.canPick)
                            FilledButton(
                              onPressed: () => widget.onPick(p),
                              child: const Text('Draften'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// Draft-Queue (Wunschliste): priorisierte Spieler, per Ziehen sortierbar.
/// Beim Auto-Pick zieht der Server den obersten noch verfügbaren Spieler.
class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.players,
    required this.canPick,
    required this.onPick,
    required this.onRemove,
    required this.onReorder,
  });

  final List<FantasyPlayer> players;
  final bool canPick;
  final Future<void> Function(FantasyPlayer) onPick;
  final ValueChanged<String> onRemove;
  final ValueChanged<List<String>> onReorder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (players.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine Spieler in der Queue.\nFüge sie im Tab „Verfügbar" '
            'mit dem Lesezeichen hinzu — auch schon vor dem Draft.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ziehen zum Sortieren. Bist du abwesend oder verpasst deinen '
                  'Pick, wird von oben automatisch gedraftet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: players.length,
            onReorderItem: (oldIndex, newIndex) {
              final ids = players.map((p) => p.id).toList();
              final item = ids.removeAt(oldIndex);
              ids.insert(newIndex, item);
              onReorder(ids);
            },
            itemBuilder: (context, i) {
              final p = players[i];
              return ListTile(
                key: ValueKey(p.id),
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  child: Text('${i + 1}',
                      style: TextStyle(fontSize: 12, color: scheme.primary)),
                ),
                title: Text(p.name),
                subtitle: Text('${p.position.short} · ${p.club}'),
                onTap: canPick ? () => onPick(p) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canPick)
                      FilledButton(
                        onPressed: () => onPick(p),
                        child: const Text('Draften'),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Entfernen',
                      icon: const Icon(Icons.close),
                      onPressed: () => onRemove(p.id),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Reihenfolge auf dem Platz: Sturm oben, Torwart unten (wie in der
/// Aufstellung).
const _pitchOrder = [
  PlayerPosition.fwd,
  PlayerPosition.mid,
  PlayerPosition.def,
  PlayerPosition.gk,
];

/// Übersicht des eigenen Kaders als Fußballfeld: pro Position die schon
/// gedrafteten Spieler plus Ziel-/Leerplätze aus der Kader-Konfig, damit man
/// beim Draften sofort sieht, wo noch Bedarf ist. Read-only.
class _MyTeamTab extends StatelessWidget {
  const _MyTeamTab(
      {required this.byPos, required this.roster, required this.clubIcons});

  final Map<PlayerPosition, List<FantasyPlayer>> byPos;
  final RosterConfig roster;
  final Map<String, String?> clubIcons;

  int _target(PlayerPosition pos) => switch (pos) {
        PlayerPosition.gk => roster.gk,
        PlayerPosition.def => roster.def,
        PlayerPosition.mid => roster.mid,
        PlayerPosition.fwd => roster.fwd,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = byPos.values.fold<int>(0, (a, l) => a + l.length);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text('$size von ${roster.squadSize} Spielern gedraftet',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Container(
            height: 440,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: pitchGradient,
            ),
            child: CustomPaint(
              painter: const PitchLinesPainter(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Column(
                  children: [
                    for (final pos in _pitchOrder)
                      Expanded(child: _row(pos)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Startelf 11 + Bank ${roster.bench} · Formation flexibel '
            '(${roster.defMin}–${roster.defMax} ABW, ${roster.midMin}–${roster.midMax} MF, '
            '${roster.fwdMin}–${roster.fwdMax} ST)',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _row(PlayerPosition pos) {
    final players = byPos[pos] ?? const <FantasyPlayer>[];
    // Leerplätze bis zum Positions-Ziel andeuten (mind. einer, wenn leer).
    final empties = (_target(pos) - players.length).clamp(0, 99);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final p in players) _chip(pos, p),
        for (var i = 0; i < empties; i++) _chip(pos, null),
      ],
    );
  }

  Widget _chip(PlayerPosition pos, FantasyPlayer? p) {
    return SizedBox(
      width: 62,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p == null)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white38, width: 1.2),
              ),
              child: const Icon(Icons.add, color: Colors.white54, size: 18),
            )
          else
            Container(
              decoration:
                  const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              padding: const EdgeInsets.all(3),
              child: ClubBadge(
                  club: p.club, iconUrl: clubIcons[p.club], size: 38),
            ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              p == null ? pos.short : _short(p.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
}

class _BoardTab extends StatelessWidget {
  const _BoardTab({
    required this.picks,
    required this.playerById,
    required this.nameById,
    required this.managers,
    required this.currentId,
    required this.myId,
  });

  final List<DraftPick> picks;
  final Map<String, FantasyPlayer> playerById;
  final Map<String, String> nameById;
  final List<FantasyManager> managers;
  final String? currentId;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _order(context),
        const Divider(height: 1),
        Expanded(
          child: picks.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Noch keine Picks — sobald der Draft läuft, erscheinen '
                        'sie hier.',
                        textAlign: TextAlign.center),
                  ),
                )
              : _pickList(context),
        ),
      ],
    );
  }

  /// Draftreihenfolge (Snake-Position 1..n), der aktuelle Manager markiert.
  Widget _order(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reihenfolge',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (i, m) in managers.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _orderChip(context,
                        pos: i + 1,
                        name: m.display,
                        isCurrent: m.userId == currentId,
                        isMine: m.userId == myId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderChip(BuildContext context,
      {required int pos,
      required String name,
      required bool isCurrent,
      required bool isMine}) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isCurrent
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    final fg = isCurrent ? scheme.onPrimary : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: isMine
            ? Border.all(color: scheme.primary, width: 1.4)
            : null,
      ),
      child: Row(
        children: [
          Text('$pos.',
              style: TextStyle(
                  color: fg.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(name,
              style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _pickList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Neueste zuerst.
    final ordered = picks.reversed.toList();
    return ListView.builder(
      itemCount: ordered.length,
      itemBuilder: (context, i) {
        final pick = ordered[i];
        final player = playerById[pick.playerId];
        final mine = pick.managerId == myId;
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: scheme.surfaceContainerHighest,
            child: Text('${pick.pickNumber}',
                style: const TextStyle(fontSize: 11)),
          ),
          title: Text(player?.name ?? pick.playerId),
          subtitle: Text(
            '${nameById[pick.managerId] ?? '—'}'
            '${pick.isAuto ? ' · Auto' : ''}',
            style: mine
                ? TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.bold)
                : null,
          ),
          trailing: player == null
              ? null
              : Text('${player.position.short} · R${pick.round}',
                  style: Theme.of(context).textTheme.labelSmall),
        );
      },
    );
  }
}
