import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_action_buttons.dart';

/// Spielersuche: durchsuchbarer Spielerpool mit Direktaktion je Spieler —
/// grün „Holen" (frei), gelb „Waiver" (auf dem Wire) oder rot „Trade"
/// (gehört einem anderen Team). Zeigt Position, Verein, Alter sowie die
/// Dynasty-Markierungen (U20, Auslands-Neuzugang).
class PlayerPoolScreen extends ConsumerStatefulWidget {
  const PlayerPoolScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<PlayerPoolScreen> createState() => _PlayerPoolScreenState();
}

class _PlayerPoolScreenState extends ConsumerState<PlayerPoolScreen> {
  String _query = '';
  PlayerPosition? _position;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final poolAsync = ref.watch(playerPoolProvider);
    final season = ref.watch(fantasySeasonProvider);
    // Stichtag für Alter/U20: ungefähr der 1. Spieltag (Saisonstart).
    final cutoff = DateTime(season, 8, 1);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final onWaivers = ref.watch(waiverPlayersProvider(league.id)).valueOrNull ??
        const <String>{};
    final claims = ref.watch(myWaiverClaimsProvider(league.id)).valueOrNull ??
        const <WaiverClaim>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;

    final ownerByPlayer = {for (final r in roster) r.playerId: r.managerId};
    final pendingClaims = claims.where((c) => c.status.isPending).toList();
    final claimedIds = {for (final c in pendingClaims) c.addPlayerId};

    return Scaffold(
      appBar: AppBar(title: const Text('Spielersuche')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (players) {
          final playerById = {for (final p in players) p.id: p};
          final myPlayers = [
            for (final r in roster)
              if (r.managerId == myId && playerById[r.playerId] != null)
                playerById[r.playerId]!
          ];

          final list = players
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
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final age = p.ageOn(cutoff);
                    final detail = <String>[
                      p.position.label,
                      p.club,
                      '$age J.',
                      if (p.isU20On(cutoff)) 'U20',
                      if (p.isForeignNewcomer) 'Ausland',
                    ].join(' · ');
                    return ListTile(
                      leading:
                          ClubBadge(club: p.club, iconUrl: clubIcons[p.club]),
                      title: Text(p.name),
                      subtitle: Text(detail),
                      trailing: PlayerActionButton(
                        league: league,
                        player: p,
                        ownerId: ownerByPlayer[p.id],
                        onWaiver: onWaivers.contains(p.id),
                        claimed: claimedIds.contains(p.id),
                        myPlayers: myPlayers,
                        nextRank: pendingClaims.length + 1,
                        myId: myId,
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
