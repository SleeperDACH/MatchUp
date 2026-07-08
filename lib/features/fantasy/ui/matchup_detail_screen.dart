import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_profile_sheet.dart';

// MatchUp-Palette (wie in der Übersicht): grün normal, rot solange live.
const _cGreen = Color(0xFF4ADE6A);
const _cRed = Color(0xFFF23030);
const _cBase = Color(0xFF12141C);

// Reihenfolge der Positionsblöcke in der Scorecard (TW zuerst).
const _order = [
  PlayerPosition.gk,
  PlayerPosition.def,
  PlayerPosition.mid,
  PlayerPosition.fwd,
];

/// Öffnet die Detailseite einer Head-to-Head-Paarung eines Spieltags.
void showMatchupDetail(
  BuildContext context, {
  required FantasyLeague league,
  required int round,
  required String homeId,
  required String homeName,
  required String? awayId,
  String? awayName,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MatchupDetailScreen(
      league: league,
      round: round,
      homeId: homeId,
      homeName: homeName,
      awayId: awayId,
      awayName: awayName,
    ),
  ));
}

/// Aufbereitete Startelf/Bank einer Seite für einen Spieltag.
class _SideData {
  _SideData(this.starters, this.bench, this.points, this.total);

  final List<FantasyPlayer> starters;
  final List<FantasyPlayer> bench;
  final Map<String, int> points;
  final int total;

  List<FantasyPlayer> startersAt(PlayerPosition pos) =>
      [for (final p in starters) if (p.position == pos) p]
        ..sort((a, b) => (points[b.id] ?? 0).compareTo(points[a.id] ?? 0));
}

/// Detailseite einer Paarung: beide Aufstellungen positionsweise
/// gegenübergestellt mit den (Live-)Punkten je Spieler. Hintergrund/Akzent
/// grün, solange der Spieltag nicht läuft — rot während er live ist. Ein
/// Bye zeigt nur die eigene Aufstellung mit „spielfrei"-Hinweis.
class MatchupDetailScreen extends ConsumerWidget {
  const MatchupDetailScreen({
    super.key,
    required this.league,
    required this.round,
    required this.homeId,
    required this.homeName,
    required this.awayId,
    this.awayName,
  });

  final FantasyLeague league;
  final int round;
  final String homeId;
  final String homeName;
  final String? awayId;
  final String? awayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final allFx =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const <Fixture>[];

    final roundFx = [for (final f in allFx) if (f.round == round) f];
    final live = roundIsLive(roundFx, DateTime.now());
    final allFinished = roundFx.isNotEmpty &&
        roundFx.every((f) => f.status == FixtureStatus.finished);
    final accent = live ? _cRed : _cGreen;
    final status = live ? 'LIVE' : (allFinished ? 'Beendet' : 'Vorschau');
    final isBye = awayId == null;

    return Scaffold(
      appBar: AppBar(title: Text('MatchUp · Spieltag $round')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final byId = {for (final p in pool) p.id: p};
          final home = _sideData(homeId, byId, roster, lineups, stats);
          final away =
              isBye ? null : _sideData(awayId!, byId, roster, lineups, stats);

          void openPlayer(FantasyPlayer p, bool mine) => showPlayerProfile(
                context,
                league: league,
                player: p,
                clubIcon: clubIcons[p.club],
                isMine: mine,
              );

          return ListView(
            children: [
              _Scoreboard(
                accent: accent,
                status: status,
                live: live,
                homeName: homeName,
                awayName: isBye ? null : (awayName ?? '?'),
                homeTotal: home.total,
                awayTotal: away?.total ?? 0,
                homeMe: homeId == myId,
                awayMe: awayId == myId,
                started: live || allFinished,
              ),
              if (isBye)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Spielfrei an diesem Spieltag — deine Aufstellung:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              const SizedBox(height: 4),
              for (final pos in _order)
                ..._positionBlock(
                  context,
                  pos: pos,
                  accent: accent,
                  home: home,
                  away: away,
                  homeMine: homeId == myId,
                  awayMine: awayId == myId,
                  clubIcons: clubIcons,
                  onTap: openPlayer,
                ),
              const SizedBox(height: 12),
              _BenchSection(
                home: home,
                away: away,
                homeName: homeName,
                awayName: isBye ? null : (awayName ?? '?'),
                clubIcons: clubIcons,
                homeMine: homeId == myId,
                awayMine: awayId == myId,
                onTap: openPlayer,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// Startelf + Bank + Punkte einer Seite (gespeicherte Aufstellung, sonst
  /// automatische beste Elf) — identisch zur Wertung im MatchUp-Tab.
  _SideData _sideData(
    String managerId,
    Map<String, FantasyPlayer> byId,
    List<RosterEntry> roster,
    List<FantasyLineup> lineups,
    Map<String, PlayerMatchStats> stats,
  ) {
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
    return _SideData(starters, bench, points, total);
  }

  /// Ein Positionsblock: Überschrift + zeilenweise Gegenüberstellung der
  /// Starter beider Seiten (nach Index innerhalb der Position gepaart).
  List<Widget> _positionBlock(
    BuildContext context, {
    required PlayerPosition pos,
    required Color accent,
    required _SideData home,
    required _SideData? away,
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

/// Kopf mit Namen, Status-Pille und Gesamt-Punktestand (grün/rot).
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.accent,
    required this.status,
    required this.live,
    required this.homeName,
    required this.awayName,
    required this.homeTotal,
    required this.awayTotal,
    required this.homeMe,
    required this.awayMe,
    required this.started,
  });

  final Color accent;
  final String status;
  final bool live;
  final String homeName;
  final String? awayName; // null = Bye
  final int homeTotal;
  final int awayTotal;
  final bool homeMe;
  final bool awayMe;
  final bool started;

  @override
  Widget build(BuildContext context) {
    final homeWin = started && awayName != null && homeTotal > awayTotal;
    final awayWin = started && awayName != null && awayTotal > homeTotal;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.42), _cBase],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 16, color: accent),
              const SizedBox(width: 4),
              Text('Head-to-Head',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              _StatusPill(accent: accent, label: status, live: live),
            ],
          ),
          const SizedBox(height: 16),
          if (awayName == null)
            Row(
              children: [
                Expanded(
                    child: _teamName(homeName, me: homeMe, win: false,
                        align: CrossAxisAlignment.start)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('spielfrei',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const Expanded(child: SizedBox()),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                    child: _teamName(homeName,
                        me: homeMe,
                        win: homeWin,
                        align: CrossAxisAlignment.start)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('$homeTotal : $awayTotal',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                    child: _teamName(awayName!,
                        me: awayMe,
                        win: awayWin,
                        align: CrossAxisAlignment.end)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _teamName(String name,
      {required bool me, required bool win, required CrossAxisAlignment align}) {
    final end = align == CrossAxisAlignment.end;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: me || win ? FontWeight.bold : FontWeight.w500)),
        const SizedBox(height: 2),
        Text(me ? 'Du' : (win ? 'Führt' : 'Gegner'),
            style:
                TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.accent, required this.label, required this.live});

  final Color accent;
  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: live ? accent : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
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
      return const SizedBox(height: 40);
    }
    final ptsBox = Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('${pts ?? 0}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: highlight ? scheme.primary : scheme.onSurface)),
    );
    final badge =
        ClubBadge(club: player.club, iconUrl: clubIcons[player.club], size: 26);
    final name = Text(_short(player.name),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: start ? TextAlign.start : TextAlign.end,
        style: TextStyle(
            fontSize: 13,
            fontWeight: mine ? FontWeight.bold : FontWeight.w500));

    final children = start
        ? [
            badge,
            const SizedBox(width: 8),
            Expanded(child: name),
            const SizedBox(width: 8),
            ptsBox,
          ]
        : [
            ptsBox,
            const SizedBox(width: 8),
            Expanded(child: name),
            const SizedBox(width: 8),
            badge,
          ];

    return InkWell(
      onTap: () => onTap(player, mine),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: children),
      ),
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
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

  final _SideData home;
  final _SideData? away;
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
                  child: _column(context, homeName, home.bench, home.points,
                      homeMine)),
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
                          club: p.club,
                          iconUrl: clubIcons[p.club],
                          size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_PlayerRow._short(p.name),
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
