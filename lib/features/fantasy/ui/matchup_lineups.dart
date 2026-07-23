import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_profile_sheet.dart';

// Reihenfolge der Positionsblöcke (TW zuerst).
const _order = [
  PlayerPosition.gk,
  PlayerPosition.def,
  PlayerPosition.mid,
  PlayerPosition.fwd,
];

/// Aufbereitete Startelf/Bank einer Seite für einen Spieltag.
class MatchupSideData {
  MatchupSideData(this.starters, this.bench, this.points, this.total);

  final List<FantasyPlayer> starters;
  final List<FantasyPlayer> bench;
  final Map<String, int> points;
  final int total;

  List<FantasyPlayer> startersAt(PlayerPosition pos) =>
      [for (final p in starters) if (p.position == pos) p]
        ..sort((a, b) => (points[b.id] ?? 0).compareTo(points[a.id] ?? 0));
}

/// Startelf + Bank + Punkte einer Seite (gespeicherte Aufstellung, sonst
/// automatische beste Elf) — identisch zur Wertung im MatchUp-Tab.
MatchupSideData computeSideData({
  required FantasyLeague league,
  required int round,
  required String managerId,
  required Map<String, FantasyPlayer> byId,
  required List<RosterEntry> roster,
  required List<FantasyLineup> lineups,
  required Map<String, PlayerMatchStats> stats,
}) {
  final rosterPlayers = [
    for (final r in roster)
      if (r.managerId == managerId && byId[r.playerId] != null)
        byId[r.playerId]!
  ];
  final pointsByPlayer = {
    for (final p in rosterPlayers)
      p: scorePlayer(
          stats[p.id] ?? const PlayerMatchStats(), p.position, league.scoring)
  };
  final saved = lineups
      .where((l) => l.managerId == managerId && l.round == round)
      .map((l) => l.playerIds)
      .firstOrNull;
  final starterIds = (saved != null && saved.isNotEmpty)
      ? {for (final id in saved) if (byId.containsKey(id)) id}
      : bestEleven(pointsByPlayer, league.roster).starterIds;

  final starters = [
    for (final p in rosterPlayers) if (starterIds.contains(p.id)) p
  ];
  final bench = [
    for (final p in rosterPlayers) if (!starterIds.contains(p.id)) p
  ]..sort((a, b) => a.position.index != b.position.index
      ? a.position.index.compareTo(b.position.index)
      : (pointsByPlayer[b] ?? 0).compareTo(pointsByPlayer[a] ?? 0));

  final points = {for (final e in pointsByPlayer.entries) e.key.id: e.value};
  final total = [for (final p in starters) points[p.id] ?? 0]
      .fold<int>(0, (a, b) => a + b);
  return MatchupSideData(starters, bench, points, total);
}

/// Spieler-Gegenüberstellung einer Head-to-Head-Paarung: beide Aufstellungen
/// positionsweise nebeneinander mit den (Live-)Punkten je Spieler, darunter
/// die ausklappbare Bank. Bei einem Bye (`away == null`) nur die eigene Seite.
/// Rendert als [Column] — passt in eine umgebende [ListView].
class MatchupLineups extends ConsumerWidget {
  const MatchupLineups({
    super.key,
    required this.league,
    required this.home,
    required this.away,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    this.awayName,
  });

  final FantasyLeague league;
  final MatchupSideData home;
  final MatchupSideData? away;
  final String homeId;
  final String? awayId;
  final String homeName;
  final String? awayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;
    final homeMine = homeId == myId;
    final awayMine = awayId != null && awayId == myId;

    void openPlayer(FantasyPlayer p, bool mine) => showPlayerProfile(
          context,
          league: league,
          player: p,
          clubIcon: clubIcons[p.club],
          isMine: mine,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pos in _order)
          ..._positionBlock(
            context,
            pos: pos,
            home: home,
            away: away,
            homeMine: homeMine,
            awayMine: awayMine,
            clubIcons: clubIcons,
            onTap: openPlayer,
          ),
        const SizedBox(height: 12),
        _BenchSection(
          home: home,
          away: away,
          homeName: homeName,
          awayName: awayName,
          clubIcons: clubIcons,
          homeMine: homeMine,
          awayMine: awayMine,
          onTap: openPlayer,
        ),
      ],
    );
  }

  /// Ein Positionsblock: Überschrift + zeilenweise Gegenüberstellung der
  /// Starter beider Seiten (nach Index innerhalb der Position gepaart).
  List<Widget> _positionBlock(
    BuildContext context, {
    required PlayerPosition pos,
    required MatchupSideData home,
    required MatchupSideData? away,
    required bool homeMine,
    required bool awayMine,
    required Map<String, String?> clubIcons,
    required void Function(FantasyPlayer, bool) onTap,
  }) {
    final hs = home.startersAt(pos);
    final as = away?.startersAt(pos) ?? const <FantasyPlayer>[];
    if (hs.isEmpty && as.isEmpty) return const [];
    final rows = <Widget>[];
    final n = hs.length > as.length ? hs.length : as.length;
    for (var i = 0; i < n; i++) {
      final h = i < hs.length ? hs[i] : null;
      final a = i < as.length ? as[i] : null;
      final hp = h == null ? null : (home.points[h.id] ?? 0);
      final ap = a == null ? null : (away?.points[a.id] ?? 0);
      rows.add(_PlayerRow(
        home: h,
        away: a,
        homePts: hp,
        awayPts: ap,
        homeMine: homeMine,
        awayMine: awayMine,
        clubIcons: clubIcons,
        onTap: onTap,
      ));
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: positionColor(pos), fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      ...rows,
    ];
  }
}

/// Eine Vergleichszeile: links Heim-Spieler, rechts Gast-Spieler, die Punkte
/// jeweils zur Mitte hin. Der punktbessere wird hervorgehoben.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.home,
    required this.away,
    required this.homePts,
    required this.awayPts,
    required this.homeMine,
    required this.awayMine,
    required this.clubIcons,
    required this.onTap,
  });

  final FantasyPlayer? home;
  final FantasyPlayer? away;
  final int? homePts;
  final int? awayPts;
  final bool homeMine;
  final bool awayMine;
  final Map<String, String?> clubIcons;
  final void Function(FantasyPlayer, bool) onTap;

  @override
  Widget build(BuildContext context) {
    final lead = homePts != null && awayPts != null
        ? (homePts! > awayPts!
            ? 1
            : awayPts! > homePts!
                ? -1
                : 0)
        : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _cell(context,
                player: home,
                pts: homePts,
                mine: homeMine,
                highlight: lead > 0,
                start: true),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _cell(context,
                player: away,
                pts: awayPts,
                mine: awayMine,
                highlight: lead < 0,
                start: false),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context,
      {required FantasyPlayer? player,
      required int? pts,
      required bool mine,
      required bool highlight,
      required bool start}) {
    final scheme = Theme.of(context).colorScheme;
    if (player == null) {
      return const SizedBox(height: 60);
    }
    final pos = positionColor(player.position);
    final ptsBox = Container(
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.22)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('${pts ?? 0}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: highlight ? scheme.primary : scheme.onSurface)),
    );
    final badge =
        ClubBadge(club: player.club, iconUrl: clubIcons[player.club], size: 34);
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          start ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(shortPlayerName(player.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: start ? TextAlign.start : TextAlign.end,
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: mine ? FontWeight.w800 : FontWeight.w600)),
        const SizedBox(height: 2),
        Text(player.position.label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                color: pos)),
      ],
    );

    final children = start
        ? [
            badge,
            const SizedBox(width: 9),
            Expanded(child: info),
            const SizedBox(width: 8),
            ptsBox,
          ]
        : [
            ptsBox,
            const SizedBox(width: 8),
            Expanded(child: info),
            const SizedBox(width: 9),
            badge,
          ];

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(player, mine),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // Karten-Look: dezenter Verlauf mit Positions-Ton.
            gradient: LinearGradient(
              begin: start ? Alignment.centerLeft : Alignment.centerRight,
              end: start ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                pos.withValues(alpha: highlight ? 0.22 : 0.13),
                scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(
              color: highlight
                  ? scheme.primary.withValues(alpha: 0.7)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: highlight ? 1.5 : 1,
            ),
            boxShadow: highlight
                ? [
                    BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.18),
                        blurRadius: 8,
                        spreadRadius: -2),
                  ]
                : null,
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}

/// Kürzt einen Spielernamen auf den Nachnamen (falls mehrteilig).
String shortPlayerName(String name) {
  final parts = name.trim().split(' ');
  return parts.length > 1 ? parts.last : name;
}

/// Ausklappbare Bank beider Seiten (zählt nicht für die Wertung).
class _BenchSection extends StatelessWidget {
  const _BenchSection({
    required this.home,
    required this.away,
    required this.homeName,
    required this.awayName,
    required this.clubIcons,
    required this.homeMine,
    required this.awayMine,
    required this.onTap,
  });

  final MatchupSideData home;
  final MatchupSideData? away;
  final String homeName;
  final String? awayName;
  final Map<String, String?> clubIcons;
  final bool homeMine;
  final bool awayMine;
  final void Function(FantasyPlayer, bool) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('Bank',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _column(
                      context, homeName, home.bench, home.points, homeMine)),
              if (awayName != null && away != null)
                Expanded(
                    child: _column(context, awayName!, away!.bench,
                        away!.points, awayMine)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _column(BuildContext context, String title, List<FantasyPlayer> bench,
      Map<String, int> points, bool mine) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (bench.isEmpty)
            Text('—',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant))
          else
            for (final p in bench)
              InkWell(
                onTap: () => onTap(p, mine),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: positionColor(p.position),
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      ClubBadge(
                          club: p.club, iconUrl: clubIcons[p.club], size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(shortPlayerName(p.name),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Text('${points[p.id] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
