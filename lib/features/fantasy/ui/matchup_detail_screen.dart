import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'matchup_lineups.dart';

// MatchUp-Palette (wie in der Übersicht): grün normal, rot solange live.
const _cGreen = Color(0xFF4ADE6A);
const _cRed = Color(0xFFF23030);
const _cBase = Color(0xFF12141C);

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
          final home = computeSideData(
              league: league,
              round: round,
              managerId: homeId,
              byId: byId,
              roster: roster,
              lineups: lineups,
              stats: stats);
          final away = isBye
              ? null
              : computeSideData(
                  league: league,
                  round: round,
                  managerId: awayId!,
                  byId: byId,
                  roster: roster,
                  lineups: lineups,
                  stats: stats);

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
              MatchupLineups(
                league: league,
                home: home,
                away: away,
                homeId: homeId,
                awayId: isBye ? null : awayId,
                homeName: homeName,
                awayName: isBye ? null : (awayName ?? '?'),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
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
