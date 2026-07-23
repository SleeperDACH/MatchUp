import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../../friends/ui/friend_action_button.dart';
import '../../messaging/ui/conversation_screen.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'pitch_painter.dart';
import 'player_profile_sheet.dart';
import 'trade_screen.dart';

// Feld: Sturm oben → TW unten (wie im Aufstellungs-Editor).
const _pitchOrder = [
  PlayerPosition.fwd,
  PlayerPosition.mid,
  PlayerPosition.def,
  PlayerPosition.gk,
];
// Bank: TW → ABW → MF → ST.
const _benchOrder = [
  PlayerPosition.gk,
  PlayerPosition.def,
  PlayerPosition.mid,
  PlayerPosition.fwd,
];

/// Öffnet das Ligaprofil eines Mitspielers: dessen Aufstellung (Startelf auf
/// dem Feld) und Bank für den aktuellen Spieltag — nur zum Ansehen.
void showManagerProfile(
  BuildContext context, {
  required FantasyLeague league,
  required String managerId,
  required String managerName,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ManagerProfileScreen(
      league: league,
      managerId: managerId,
      managerName: managerName,
    ),
  ));
}

class ManagerProfileScreen extends ConsumerWidget {
  const ManagerProfileScreen({
    super.key,
    required this.league,
    required this.managerId,
    required this.managerName,
  });

  final FantasyLeague league;
  final String managerId;
  final String managerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = ref.watch(fantasyCurrentRoundProvider).valueOrNull ?? 34;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final stats = ref.watch(roundStatsProvider(round)).valueOrNull ??
        const <String, PlayerMatchStats>{};
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];
    final isMe = managerId == myId;
    final manager =
        managers.where((m) => m.userId == managerId).firstOrNull;
    final display = manager?.display ?? managerName;
    // Zweiter Name (echter Nutzername) nur zeigen, wenn ein Teamname gesetzt ist.
    final showUsername =
        manager != null && (manager.teamName?.trim().isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(
              imageUrl: manager?.avatarUrl,
              emoji: manager?.avatarEmoji,
              colorHex: manager?.avatarColor,
              fallbackText: display,
              size: 32,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(display, overflow: TextOverflow.ellipsis),
                  if (showUsername)
                    Text('@${manager.username}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Aufstellung · Spieltag $round',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      ),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final byId = {for (final p in pool) p.id: p};
          final rosterPlayers = [
            for (final r in roster)
              if (r.managerId == managerId && byId[r.playerId] != null)
                byId[r.playerId]!
          ];
          if (rosterPlayers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Dieser Manager hat noch keinen Kader.',
                    textAlign: TextAlign.center),
              ),
            );
          }

          final points = {
            for (final p in rosterPlayers)
              p: scorePlayer(stats[p.id] ?? const PlayerMatchStats(),
                  p.position, league.scoring)
          };

          // Gespeicherte Aufstellung des Spieltags, sonst beste Elf.
          final saved = lineups
              .where((l) => l.managerId == managerId && l.round == round)
              .map((l) => l.playerIds)
              .firstOrNull;
          final Set<String> starterIds =
              (saved != null && saved.isNotEmpty)
                  ? {
                      for (final id in saved)
                        if (byId.containsKey(id)) id
                    }
                  : bestEleven(points, league.roster).starterIds;

          final starters = [
            for (final p in rosterPlayers)
              if (starterIds.contains(p.id)) p
          ];
          final bench = [
            for (final p in rosterPlayers)
              if (!starterIds.contains(p.id)) p
          ]..sort((a, b) => a.position.index != b.position.index
              ? a.position.index.compareTo(b.position.index)
              : (points[b] ?? 0).compareTo(points[a] ?? 0));

          final byPos = <PlayerPosition, List<FantasyPlayer>>{};
          for (final p in starters) {
            byPos.putIfAbsent(p.position, () => []).add(p);
          }

          void openPlayer(FantasyPlayer p) => showPlayerProfile(
                context,
                league: league,
                player: p,
                clubIcon: clubIcons[p.club],
                isMine: isMe,
              );

          return ListView(
            children: [
              if (!isMe) _actions(context, ref, managers),
              _pitch(context, byPos, points, clubIcons, openPlayer),
              _bench(context, bench, points, clubIcons, openPlayer),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  Widget _actions(
      BuildContext context, WidgetRef ref, List<FantasyManager> managers) {
    FantasyManager? m;
    for (final x in managers) {
      if (x.userId == managerId) {
        m = x;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          // Freund hinzufügen (liga-unabhängig, aber hier direkt erreichbar).
          Align(
            alignment: Alignment.centerLeft,
            child: FriendActionButton(userId: managerId),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: m == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              TradeComposeScreen(league: league, partner: m!))),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Trade'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ConversationScreen(
                            partnerId: managerId,
                            partnerName: managerName,
                          ))),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Nachricht'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pitch(
    BuildContext context,
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
    Map<FantasyPlayer, int> points,
    Map<String, String?> clubIcons,
    void Function(FantasyPlayer) onTap,
  ) {
    return Container(
      margin: const EdgeInsets.all(12),
      height: 420,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: pitchGradient,
      ),
      child: CustomPaint(
        painter: const PitchLinesPainter(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            children: [
              for (final pos in _pitchOrder)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final p in (byPos[pos] ?? const <FantasyPlayer>[]))
                        _pitchPlayer(
                            p, points[p] ?? 0, clubIcons[p.club], () => onTap(p)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pitchPlayer(
      FantasyPlayer p, int pts, String? icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
      width: 66,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClubBadge(club: p.club, iconUrl: icon, size: 42),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$pts',
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
            child: Text(_short(p.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
          const SizedBox(height: 3),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: positionColor(p.position),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _bench(
    BuildContext context,
    List<FantasyPlayer> bench,
    Map<FantasyPlayer, int> points,
    Map<String, String?> clubIcons,
    void Function(FantasyPlayer) onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bank (${bench.length})',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (bench.isEmpty)
            Text('Alle Spieler stehen in der Startelf.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant))
          else
            for (final pos in _benchOrder)
              if (bench.any((p) => p.position == pos)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: positionColor(pos), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(pos.label,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                  color: positionColor(pos),
                                  fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in bench)
                      if (p.position == pos)
                        GestureDetector(
                          onTap: () => onTap(p),
                          child: Chip(
                            avatar: ClubBadge(
                                club: p.club,
                                iconUrl: clubIcons[p.club],
                                size: 22),
                            side: BorderSide(
                                color: positionColor(p.position)
                                    .withValues(alpha: 0.6)),
                            label:
                                Text('${_short(p.name)} · ${points[p] ?? 0}'),
                          ),
                        ),
                  ],
                ),
              ],
        ],
      ),
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
}
