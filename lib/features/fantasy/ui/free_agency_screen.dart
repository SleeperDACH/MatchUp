import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'player_flag.dart';

/// Free Agency: alle Spieler, die in keinem Kader sind. Aufnahme
/// respektiert die Kadergröße (sonst Drop nötig) und die 05.09.-Sperre
/// für U20/Auslands-Neuzugänge.
///
/// (Direkte Aufnahme = freie Aufnahme nach dem Waiver-Wire. Die
/// terminierten Waiver-Anträge folgen als nächster Schritt.)
class FreeAgencyScreen extends ConsumerStatefulWidget {
  const FreeAgencyScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<FreeAgencyScreen> createState() => _FreeAgencyScreenState();
}

class _FreeAgencyScreenState extends ConsumerState<FreeAgencyScreen> {
  String _query = '';
  PlayerPosition? _position;

  Future<void> _add(FantasyPlayer player, List<FantasyPlayer> myPlayers) async {
    final league = widget.league;
    String? dropId;

    // Kader voll -> Spieler zum Abgeben wählen.
    if (myPlayers.length >= league.roster.squadSize) {
      dropId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Kader voll — wen abgeben?'),
          children: [
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
      if (dropId == null) return;
    }

    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .addFreeAgent(league.id, player.id, dropPlayerId: dropId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${player.name} aufgenommen')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Free Agency')),
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
            ..sort((a, b) => a.name.compareTo(b.name));

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
                    return ListTile(
                      leading: PlayerFlag(code: p.nationality),
                      title: Text(p.name),
                      subtitle: Text('${p.position.short} · ${p.club}'),
                      trailing: locked
                          ? const _LockedChip()
                          : FilledButton(
                              onPressed: () => _add(p, myPlayers),
                              child: const Text('Holen'),
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

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
            label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
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
