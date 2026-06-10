import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/draft_order.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'player_flag.dart';

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

  String get _leagueId => widget.league.id;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onTick() {
    final league = ref.read(draftLeagueProvider(_leagueId)).valueOrNull;
    if (league != null &&
        league.draftStatus == DraftStatus.drafting &&
        league.currentPickDeadline != null &&
        !_autopickInFlight &&
        DateTime.now().isAfter(
            league.currentPickDeadline!.add(const Duration(seconds: 1)))) {
      _autopickInFlight = true;
      ref
          .read(draftRepositoryProvider)
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
            : msg.contains('bereits gedraftet')
                ? 'Der Spieler wurde schon gedraftet.'
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
    final myId = ref.watch(currentUserProvider)?.id;

    if (managersAsync.isLoading || poolAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final managers = [...managersAsync.requireValue]
      ..sort((a, b) => (a.draftPosition ?? 99).compareTo(b.draftPosition ?? 99));
    final pool = poolAsync.requireValue;
    final picks = picksAsync.valueOrNull ?? const <DraftPick>[];

    final playerById = {for (final p in pool) p.id: p};
    final nameById = {for (final m in managers) m.userId: m.username};
    final pickedIds = {for (final p in picks) p.playerId};
    final available =
        pool.where((p) => !pickedIds.contains(p.id)).toList();

    final cur = currentManager(managers, league.picksMade);
    final myTurn = league.draftStatus == DraftStatus.drafting &&
        cur != null &&
        cur.userId == myId;
    final total = totalPicks(managers.length, league.roster);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(league.name),
          bottom: const TabBar(tabs: [
            Tab(text: 'Verfügbar'),
            Tab(text: 'Board'),
          ]),
        ),
        body: Column(
          children: [
            _StatusBanner(
              league: league,
              current: cur,
              myTurn: myTurn,
              total: total,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AvailableTab(
                    players: available,
                    canPick: myTurn,
                    onPick: _pick,
                  ),
                  _BoardTab(
                    picks: picks,
                    playerById: playerById,
                    nameById: nameById,
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
  });

  final FantasyLeague league;
  final FantasyManager? current;
  final bool myTurn;
  final int total;

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
          child: const Text('Draft noch nicht gestartet'));
    }

    final remaining = league.currentPickDeadline == null
        ? Duration.zero
        : league.currentPickDeadline!.difference(DateTime.now());
    final secs = remaining.inSeconds.clamp(0, 1 << 31);
    final clock =
        '${(secs ~/ 60)}:${(secs % 60).toString().padLeft(2, '0')}';

    return _bar(
      context,
      myTurn ? scheme.primary.withValues(alpha: 0.18) : scheme.surfaceContainerHigh,
      child: Column(
        children: [
          Text(
            'Runde ${(league.picksMade ~/ (total ~/ league.roster.squadSize).clamp(1, 99)) + 1} · Pick ${league.picksMade + 1} von $total',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(myTurn ? Icons.sports : Icons.timer,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                myTurn
                    ? 'Du bist dran!'
                    : 'Am Zug: ${current?.username ?? '—'}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: myTurn ? scheme.primary : null),
              ),
              const SizedBox(width: 12),
              Text(clock,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [],
                      color: secs <= 10 ? scheme.error : null)),
            ],
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
  });

  final List<FantasyPlayer> players;
  final bool canPick;
  final Future<void> Function(FantasyPlayer) onPick;

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
                    return ListTile(
                      leading: PlayerFlag(code: p.nationality),
                      title: Text(p.name),
                      subtitle: Text('${p.position.short} · ${p.club}'),
                      trailing: widget.canPick
                          ? FilledButton(
                              onPressed: () => widget.onPick(p),
                              child: const Text('Draften'),
                            )
                          : null,
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

class _BoardTab extends StatelessWidget {
  const _BoardTab({
    required this.picks,
    required this.playerById,
    required this.nameById,
    required this.myId,
  });

  final List<DraftPick> picks;
  final Map<String, FantasyPlayer> playerById;
  final Map<String, String> nameById;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    if (picks.isEmpty) {
      return const Center(child: Text('Noch keine Picks.'));
    }
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
