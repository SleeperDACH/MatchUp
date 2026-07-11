import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// Optimistische Queue-Reihenfolge: sofort angezeigt (kein „Zurückspringen"
  /// beim Sortieren), bis der Realtime-Stream denselben Stand meldet.
  List<String>? _optimisticQueue;

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

  /// Admin: Draft-Reihenfolge zufällig mischen (persistiert, sofort im Board
  /// sichtbar). Setzt die Positionen per Reihenfolge (Modus wird 'manual').
  Future<void> _shuffleOrder(List<FantasyManager> managers) async {
    final messenger = ScaffoldMessenger.of(context);
    if (managers.length < 2) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Zum Mischen müssen mindestens 2 Teams beigetreten '
              'sein. Freie Platzhalter-Teams draften nicht mit.')));
      return;
    }
    final ids = managers.map((m) => m.userId).toList()..shuffle();
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .setDraftOrder(_leagueId, ids);
      ref.invalidate(fantasyManagersProvider(_leagueId));
      ref.invalidate(draftLeagueProvider(_leagueId));
      messenger.showSnackBar(
          const SnackBar(content: Text('Draft-Reihenfolge gemischt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  /// Admin: Draft starten (nach Bestätigung).
  Future<void> _startDraft(FantasyLeague league) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Draft starten?'),
        content: Text(
            'Der Draft startet mit der aktuellen Reihenfolge und kann nicht '
            'mehr geändert werden. ${league.draftOrderMode == 'manual' ? '' : 'Die Reihenfolge wird beim Start zufällig ausgelost.'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Starten')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.startDraft(_leagueId);
      ref.invalidate(draftLeagueProvider(_leagueId));
      ref.invalidate(fantasyManagersProvider(_leagueId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  /// Speichert die eigene Draft-Queue optimistisch: zeigt die neue Reihenfolge
  /// sofort (setState) und persistiert sie. Bei Fehler wird zurückgesetzt und
  /// eine Snackbar gezeigt. Der Realtime-Stream übernimmt danach (das
  /// `ref.listen` in build hebt die optimistische Sicht wieder auf).
  Future<void> _applyQueue(List<String> ids) async {
    setState(() => _optimisticQueue = ids);
    try {
      await _repo.setQueue(_leagueId, ids);
    } catch (e) {
      if (!mounted) return;
      setState(() => _optimisticQueue = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Queue konnte nicht gespeichert werden: $e')));
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
    final streamQueue =
        ref.watch(draftQueueProvider(_leagueId)).valueOrNull ?? const <String>[];
    // Optimistische Reihenfolge fallenlassen, sobald der Stream sie bestätigt.
    ref.listen(draftQueueProvider(_leagueId), (_, next) {
      final v = next.valueOrNull;
      if (v != null &&
          _optimisticQueue != null &&
          listEquals(v, _optimisticQueue)) {
        setState(() => _optimisticQueue = null);
      }
    });
    final queueIds = _optimisticQueue ?? streamQueue;
    final queueSet = queueIds.toSet();
    final queuePlayers = [
      for (final id in queueIds)
        if (playerById[id] != null) playerById[id]!
    ];
    void toggleQueue(String id) {
      final list = [...queueIds];
      list.contains(id) ? list.remove(id) : list.add(id);
      unawaited(_applyQueue(list));
    }

    final cur = currentManager(managers, league.picksMade);
    final myTurn = league.draftStatus == DraftStatus.drafting &&
        cur != null &&
        cur.userId == myId;
    final total = managers.length * league.roundsThisPhase;
    final round =
        managers.isEmpty ? 1 : league.picksMade ~/ managers.length + 1;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(league.name),
          // Board zuerst, dann Spieler (mit Queue als Unter-Tab) und Team.
          bottom: TabBar(
            labelPadding: EdgeInsets.zero,
            tabs: [
              const Tab(
                  icon: Icon(Icons.grid_view_outlined, size: 20),
                  text: 'Board'),
              const Tab(
                  icon: Icon(Icons.groups_2_outlined, size: 20),
                  text: 'Spieler'),
              Tab(
                  icon: const Icon(Icons.shield_outlined, size: 20),
                  text: 'Team ($mySquadSize)'),
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
            // Setup-Hinweis für alle: Queue kann schon jetzt vorbereitet werden.
            if (league.draftStatus == DraftStatus.setup)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_add_outlined,
                        size: 15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Schon jetzt: Im Tab „Spieler" deine Draft-Queue '
                        'vorbereiten. Freie Plätze (Team N) füllen sich, sobald '
                        'Spieler beitreten.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            // Admin-Steuerung im Setup: Reihenfolge mischen + Draft starten.
            if (league.draftStatus == DraftStatus.setup &&
                myId == league.createdBy)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      // Immer tippbar (nicht ausgegraut); erklärt, falls noch
                      // nicht genug Teams beigetreten sind.
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Order mischen'),
                        onPressed: () => _shuffleOrder(managers),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.sports, size: 18),
                        label: const Text('Draft starten'),
                        onPressed:
                            managers.isEmpty ? null : () => _startDraft(league),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _BoardTab(
                    picks: phasePicks,
                    playerById: playerById,
                    managers: managers,
                    maxTeams: league.maxTeams,
                    rounds: league.roundsThisPhase,
                    currentManagerId: league.draftStatus == DraftStatus.drafting
                        ? cur?.userId
                        : null,
                    currentRound: round,
                    myId: myId,
                  ),
                  // Spieler-Tab mit Unter-Tabs: Verfügbar + Queue.
                  _PlayersTab(
                    available: _AvailableTab(
                      players: available,
                      canPick: myTurn,
                      onPick: _pick,
                      queued: queueSet,
                      onToggleQueue: toggleQueue,
                      clubIcons: clubIcons,
                    ),
                    queue: _QueueTab(
                      players: queuePlayers,
                      canPick: myTurn,
                      onPick: _pick,
                      onRemove: toggleQueue,
                      onReorder: (ids) => unawaited(_applyQueue(ids)),
                    ),
                    queueCount: queuePlayers.length,
                  ),
                  _MyTeamTab(
                      byPos: mySquad,
                      roster: league.roster,
                      clubIcons: clubIcons),
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

  /// Feste Startelf-Formation 4-3-3 (TW 1, ABW 4, MF 3, ST 3). Überzählige
  /// Spieler einer Position landen auf der Bank.
  int _starters(PlayerPosition pos) => switch (pos) {
        PlayerPosition.gk => 1,
        PlayerPosition.def => 4,
        PlayerPosition.mid => 3,
        PlayerPosition.fwd => 3,
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
            'Feste Startelf 4-3-3 · überzählige Spieler kommen auf die Bank',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          _bench(context),
        ],
      ),
    );
  }

  /// Bank: alle Spieler, die über die feste 4-3-3-Startelf hinausgehen
  /// (z. B. der 5. Abwehrspieler).
  Widget _bench(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bench = <(PlayerPosition, FantasyPlayer)>[];
    for (final pos in _pitchOrder) {
      final players = byPos[pos] ?? const <FantasyPlayer>[];
      for (final p in players.skip(_starters(pos))) {
        bench.add((pos, p));
      }
    }
    if (bench.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bank (${bench.length})',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (pos, p) in bench)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClubBadge(
                          club: p.club, iconUrl: clubIcons[p.club], size: 22),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_short(p.name),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(pos.short,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(PlayerPosition pos) {
    final players = byPos[pos] ?? const <FantasyPlayer>[];
    final target = _starters(pos);
    // Nur die Startelf-Plätze zeigen; Überzählige stehen auf der Bank.
    final starters = players.take(target).toList();
    final empties = (target - starters.length).clamp(0, 99);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final p in starters) _chip(pos, p),
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

/// Spieler-Tab mit Unter-Tabs: „Verfügbar" (Spielerliste) und „Queue".
class _PlayersTab extends StatelessWidget {
  const _PlayersTab({
    required this.available,
    required this.queue,
    required this.queueCount,
  });

  final Widget available;
  final Widget queue;
  final int queueCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: scheme.primary,
            tabs: [
              const Tab(text: 'Verfügbar'),
              Tab(text: 'Queue ($queueCount)'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [available, queue]),
          ),
        ],
      ),
    );
  }
}

/// Eine Board-Spalte: entweder ein echter Teilnehmer oder ein freies
/// Platzhalter-Team (Team N).
class _BoardCol {
  const _BoardCol(
      {required this.label, this.userId, this.mine = false, this.autoPick = false});
  final String label;
  final String? userId; // null = Platzhalter
  final bool mine;
  final bool autoPick;
}

// Board-Farben: beigetretene Teams grün, das aktuell ziehende Team rot.
const _cBoardGreen = Color(0xFF4ADE6A);
const _cBoardRed = Color(0xFFF23030);
const _cBoardInk = Color(0xFF12141C);

/// Kopfzelle einer Board-Spalte: farbiger Hintergrund (grün beigetreten, rot am
/// Zug, neutral für Platzhalter) plus optionales „AUTO"-Badge.
class _BoardHeaderCell extends StatelessWidget {
  const _BoardHeaderCell({
    required this.col,
    required this.isCurrent,
    required this.width,
    required this.scheme,
    required this.child,
  });

  final _BoardCol col;
  final bool isCurrent;
  final double width;
  final ColorScheme scheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final placeholder = col.userId == null;
    final Color bg = placeholder
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : (isCurrent ? _cBoardRed : _cBoardGreen);
    return Container(
      width: width,
      margin: const EdgeInsets.all(1.5),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          if (col.autoPick) ...[
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _cBoardInk.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.smart_toy_outlined, size: 10, color: _cBoardInk),
                  SizedBox(width: 3),
                  Text('AUTO',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: _cBoardInk)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Draft-Board als Raster: Spalten = Teams (Draft-Reihenfolge, inkl. freier
/// Platzhalter-Teams bis zur Teilnehmerzahl), Zeilen = Runden. Jede Zelle zeigt
/// den Pick-Code (1.01, 1.02 …) und – falls schon gepickt – den Spieler. Der
/// aktuelle Pick ist hervorgehoben.
class _BoardTab extends StatelessWidget {
  const _BoardTab({
    required this.picks,
    required this.playerById,
    required this.managers,
    required this.maxTeams,
    required this.rounds,
    required this.currentManagerId,
    required this.currentRound,
    required this.myId,
  });

  final List<DraftPick> picks;
  final Map<String, FantasyPlayer> playerById;
  final List<FantasyManager> managers;
  final int? maxTeams;
  final int rounds;
  final String? currentManagerId;
  final int currentRound;
  final String? myId;

  static const _colW = 92.0;
  static const _rowH = 52.0;
  static const _labelW = 34.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (managers.isEmpty || rounds <= 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sobald der Draft startet, erscheint hier das Board.',
              textAlign: TextAlign.center),
        ),
      );
    }
    // Echte Teams nach Draft-Position (Slot 1..); ohne Position stabil ans Ende.
    final real = [...managers]..sort((a, b) {
        final pa = a.draftPosition ?? 1 << 30;
        final pb = b.draftPosition ?? 1 << 30;
        return pa.compareTo(pb);
      });
    // Spalten = echte Teams + freie Platzhalter-Teams bis zur Teilnehmerzahl.
    final cols = <_BoardCol>[
      for (final m in real)
        _BoardCol(
            label: m.display,
            userId: m.userId,
            mine: m.userId == myId,
            autoPick: m.autoPick),
    ];
    final target = (maxTeams != null && maxTeams! > cols.length)
        ? maxTeams!
        : cols.length;
    for (var i = cols.length; i < target; i++) {
      cols.add(_BoardCol(label: 'Team ${i + 1}'));
    }
    final n = cols.length;
    // Pick je (Runde, Manager) für schnellen Zugriff.
    final pickByCell = <String, DraftPick>{
      for (final p in picks) '${p.round}:${p.managerId}': p,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kopfzeile: beigetretene Teams grün, das ziehende Team rot,
            // Platzhalter neutral. Auto-Pick-Teams zeigen ein „AUTO"-Badge.
            Row(
              children: [
                const SizedBox(width: _labelW),
                for (final c in cols)
                  _BoardHeaderCell(
                    col: c,
                    isCurrent: c.userId != null && c.userId == currentManagerId,
                    width: _colW,
                    scheme: scheme,
                    child: Text(
                      c.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.userId == null
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                            : _cBoardInk,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1),
            for (var r = 1; r <= rounds; r++)
              Row(
                children: [
                  SizedBox(
                    width: _labelW,
                    height: _rowH,
                    child: Center(
                      child: Text('R$r',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                  ),
                  for (var s = 0; s < n; s++)
                    _cell(context, round: r, slot: s, n: n,
                        col: cols[s],
                        pick: cols[s].userId == null
                            ? null
                            : pickByCell['$r:${cols[s].userId}'],
                        isCurrent: cols[s].userId != null &&
                            cols[s].userId == currentManagerId &&
                            r == currentRound),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context,
      {required int round,
      required int slot,
      required int n,
      required _BoardCol col,
      required DraftPick? pick,
      required bool isCurrent}) {
    final scheme = Theme.of(context).colorScheme;
    // Snake: ungerade Runden vorwärts, gerade rückwärts (0-basiert: round-1).
    final round0 = round - 1;
    final pickInRound = round0.isEven ? slot + 1 : n - slot;
    final code = '$round.${pickInRound.toString().padLeft(2, '0')}';
    final player = pick == null ? null : playerById[pick.playerId];
    final mine = col.mine;
    final placeholder = col.userId == null;

    return Container(
      width: _colW,
      height: _rowH,
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: player != null
            ? (mine
                ? scheme.primary.withValues(alpha: 0.18)
                : scheme.surfaceContainerHighest)
            : scheme.surfaceContainerHighest
                .withValues(alpha: placeholder ? 0.15 : 0.3),
        borderRadius: BorderRadius.circular(8),
        border: isCurrent
            ? Border.all(color: scheme.primary, width: 1.6)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(code,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant
                          .withValues(alpha: placeholder ? 0.5 : 1.0))),
              if (pick?.isAuto ?? false) ...[
                const SizedBox(width: 3),
                Text('A',
                    style: TextStyle(
                        fontSize: 9,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            player?.name ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: player != null
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
