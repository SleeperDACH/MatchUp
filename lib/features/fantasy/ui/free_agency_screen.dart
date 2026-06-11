import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'player_flag.dart';
import 'waiver_claims_screen.dart';

/// Free Agency & Waiver-Wire.
///
/// * Echte Free Agents (nie gedraftet oder vom Wire gefallen) sind sofort
///   holbar — respektiert Kadergröße (sonst Drop nötig) und die 05.09.-Sperre.
/// * Frisch gedroppte Spieler liegen bis zur nächsten Deadline (2 Tage vor
///   dem Spieltag) auf dem Waiver-Wire und sind nur per Antrag holbar; die
///   Anträge werden terminiert in Prioritätsreihenfolge abgearbeitet.
class FreeAgencyScreen extends ConsumerStatefulWidget {
  const FreeAgencyScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<FreeAgencyScreen> createState() => _FreeAgencyScreenState();
}

class _FreeAgencyScreenState extends ConsumerState<FreeAgencyScreen> {
  String _query = '';
  PlayerPosition? _position;

  /// Lässt – falls der Kader voll ist – einen abzugebenden Spieler wählen.
  /// [optional] = true erlaubt „keinen abgeben" (nur wenn Platz frei).
  Future<String?> _chooseDrop(
    List<FantasyPlayer> myPlayers, {
    required bool optional,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
            optional ? 'Wen abgeben? (optional)' : 'Kader voll — wen abgeben?'),
        children: [
          if (optional)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Keinen — nur bei freiem Platz'),
            ),
          for (final p in myPlayers)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p.id),
              child: Text('${p.position.short} · ${p.name}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  Future<void> _add(FantasyPlayer player, List<FantasyPlayer> myPlayers) async {
    final league = widget.league;
    String? dropId;

    if (myPlayers.length >= league.roster.squadSize) {
      dropId = await _chooseDrop(myPlayers, optional: false);
      if (dropId == null) return; // abgebrochen
    }

    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .addFreeAgent(league.id, player.id, dropPlayerId: dropId);
      _toast('${player.name} aufgenommen');
    } catch (e) {
      _toast('Fehlgeschlagen: $e');
    }
  }

  Future<void> _claim(
    FantasyPlayer player,
    List<FantasyPlayer> myPlayers,
    int nextRank,
  ) async {
    // Drop ist beim Waiver-Antrag optional (Kader kann bis dahin Platz haben).
    final dropChoice = await _chooseDrop(myPlayers, optional: true);
    if (dropChoice == null) return; // abgebrochen
    final dropId = dropChoice.isEmpty ? null : dropChoice;

    try {
      await ref.read(fantasyLeagueRepositoryProvider).submitWaiverClaim(
            widget.league.id,
            player.id,
            dropPlayerId: dropId,
            rank: nextRank,
          );
      _toast('Antrag für ${player.name} gestellt');
    } catch (e) {
      _toast('Fehlgeschlagen: $e');
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final onWaivers = ref.watch(waiverPlayersProvider(league.id)).valueOrNull ??
        const <String>{};
    final claims = ref.watch(myWaiverClaimsProvider(league.id)).valueOrNull ??
        const <WaiverClaim>[];
    final window = ref.watch(waiverWindowProvider).valueOrNull;
    final myId = ref.watch(currentUserProvider)?.id;

    final pendingClaims = claims.where((c) => c.status.isPending).toList();
    final claimedPlayerIds = {for (final c in pendingClaims) c.addPlayerId};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Free Agency'),
        actions: [
          IconButton(
            tooltip: 'Meine Anträge',
            icon: Badge(
              isLabelVisible: pendingClaims.isNotEmpty,
              label: Text('${pendingClaims.length}'),
              child: const Icon(Icons.assignment_outlined),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WaiverClaimsScreen(league: league))),
          ),
        ],
      ),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final playerById = {for (final p in pool) p.id: p};
          final rosteredIds = {for (final r in roster) r.playerId};
          final myPlayers = [
            for (final r in roster)
              if (r.managerId == myId && playerById[r.playerId] != null)
                playerById[r.playerId]!
          ];

          final freeAgents = pool
              .where((p) => !rosteredIds.contains(p.id))
              .where((p) => _position == null || p.position == _position)
              .where((p) =>
                  _query.isEmpty ||
                  p.name.toLowerCase().contains(_query.toLowerCase()) ||
                  p.club.toLowerCase().contains(_query.toLowerCase()))
              .toList()
            ..sort((a, b) {
              // Wire-Spieler zuerst — die spannenden Neuzugänge.
              final aw = onWaivers.contains(a.id) ? 0 : 1;
              final bw = onWaivers.contains(b.id) ? 0 : 1;
              return aw != bw ? aw - bw : a.name.compareTo(b.name);
            });

          return Column(
            children: [
              _WaiverBanner(round: window?.round, deadline: window?.deadline),
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
                    _chip('Alle', _position == null,
                        () => setState(() => _position = null)),
                    for (final pos in PlayerPosition.values)
                      _chip(pos.label, _position == pos,
                          () => setState(() => _position = pos)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: freeAgents.length,
                  itemBuilder: (context, i) {
                    final p = freeAgents[i];
                    final locked = p.isLockedNow(league.season);
                    final waiver = onWaivers.contains(p.id);
                    final claimed = claimedPlayerIds.contains(p.id);
                    return ListTile(
                      leading: PlayerFlag(code: p.nationality),
                      title: Text(p.name),
                      subtitle: Text(waiver
                          ? '${p.position.short} · ${p.club} · Waiver-Wire'
                          : '${p.position.short} · ${p.club}'),
                      trailing: _trailing(
                        player: p,
                        locked: locked,
                        waiver: waiver,
                        claimed: claimed,
                        myPlayers: myPlayers,
                        nextRank: pendingClaims.length + 1,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _trailing({
    required FantasyPlayer player,
    required bool locked,
    required bool waiver,
    required bool claimed,
    required List<FantasyPlayer> myPlayers,
    required int nextRank,
  }) {
    if (locked) return const _LockedChip();
    if (waiver) {
      if (claimed) {
        return const Chip(
          visualDensity: VisualDensity.compact,
          label: Text('Beantragt'),
        );
      }
      return OutlinedButton(
        onPressed: () => _claim(player, myPlayers, nextRank),
        child: const Text('Beantragen'),
      );
    }
    return FilledButton(
      onPressed: () => _add(player, myPlayers),
      child: const Text('Holen'),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
            label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

/// Hinweis auf die nächste Waiver-Deadline.
class _WaiverBanner extends StatelessWidget {
  const _WaiverBanner({this.round, this.deadline});

  final int? round;
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = deadline == null
        ? 'Kein Spieltag in Sicht — gedroppte Spieler sind sofort frei.'
        : 'Waiver-Anträge für Spieltag $round bis '
            '${_fmt(deadline!)} · danach Direkt-Aufnahme frei.';
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer)),
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

class _LockedChip extends StatelessWidget {
  const _LockedChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text('U20-Draft',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
