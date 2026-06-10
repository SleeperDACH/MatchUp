import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'player_flag.dart';

/// Durchsuchbarer Spielerpool. Zeigt Position, Verein, Alter sowie die
/// für Dynasty relevanten Markierungen (U20, Auslands-Neuzugang).
class PlayerPoolScreen extends ConsumerStatefulWidget {
  const PlayerPoolScreen({super.key});

  @override
  ConsumerState<PlayerPoolScreen> createState() => _PlayerPoolScreenState();
}

class _PlayerPoolScreenState extends ConsumerState<PlayerPoolScreen> {
  String _query = '';
  PlayerPosition? _position;

  @override
  Widget build(BuildContext context) {
    final pool = ref.watch(playerPoolProvider);
    final season = ref.watch(fantasySeasonProvider);
    // Stichtag für Alter/U20: ungefähr der 1. Spieltag (Saisonstart).
    final cutoff = DateTime(season, 8, 1);

    return Scaffold(
      appBar: AppBar(title: const Text('Spielerpool')),
      body: pool.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (players) {
          var list = players
              .where((p) =>
                  _position == null || p.position == _position)
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
                    _FilterChip(
                      label: 'Alle',
                      selected: _position == null,
                      onTap: () => setState(() => _position = null),
                    ),
                    for (final pos in PlayerPosition.values)
                      _FilterChip(
                        label: pos.label,
                        selected: _position == pos,
                        onTap: () => setState(() => _position = pos),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) =>
                      _PlayerTile(player: list[i], cutoff: cutoff),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.cutoff});

  final FantasyPlayer player;
  final DateTime cutoff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final age = player.ageOn(cutoff);
    return ListTile(
      leading: PlayerFlag(code: player.nationality),
      title: Text(player.name),
      subtitle: Text('${player.position.label} · ${player.club}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$age J.', style: Theme.of(context).textTheme.bodyMedium),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (player.isU20On(cutoff))
                _Badge(text: 'U20', color: scheme.primary),
              if (player.isForeignNewcomer)
                _Badge(text: 'Ausland', color: scheme.tertiary),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
