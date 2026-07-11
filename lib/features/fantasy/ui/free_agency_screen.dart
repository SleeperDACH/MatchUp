import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_action_buttons.dart';
import 'waiver_claims_screen.dart';

/// Free Agency & Waiver-Wire.
///
/// * Echte Free Agents (nie gedraftet oder vom Wire gefallen) sind sofort
///   holbar — respektiert Kadergröße (sonst Drop nötig) und die 05.09.-Sperre.
/// * Frisch gedroppte Spieler liegen 24 Stunden auf dem Waiver-Wire und sind
///   nur per Antrag holbar; nach Ablauf werden die Anträge in
///   Prioritätsreihenfolge abgearbeitet, sonst wird der Spieler frei.
class FreeAgencyScreen extends ConsumerStatefulWidget {
  const FreeAgencyScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<FreeAgencyScreen> createState() => _FreeAgencyScreenState();
}

class _FreeAgencyScreenState extends ConsumerState<FreeAgencyScreen> {
  String _query = '';
  PlayerPosition? _position;

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
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
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
              const _WaiverBanner(),
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
                    final waiver = onWaivers.contains(p.id);
                    final claimed = claimedPlayerIds.contains(p.id);
                    return ListTile(
                      leading: ClubBadge(club: p.club, iconUrl: clubIcons[p.club]),
                      title: Text(p.name),
                      subtitle: Row(
                        children: [
                          PositionPill(pos: p.position),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                waiver ? '${p.club} · Waiver-Wire' : p.club,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      trailing: PlayerActionButton(
                        league: league,
                        player: p,
                        ownerId: null,
                        onWaiver: waiver,
                        claimed: claimed,
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

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
            label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

/// Hinweis auf die Waiver-Regel (24 Stunden je gedropptem Spieler).
class _WaiverBanner extends StatelessWidget {
  const _WaiverBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Gedroppte Spieler sind 24 Stunden nur per Antrag holbar '
                '(Waiver, rollende Priorität) — danach frei.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer)),
          ),
        ],
      ),
    );
  }
}
