/// Wochen-Recap & Awards eines Fantasy-Spieltags.
///
/// Reine, sport-/ligaunabhängige Auswertung: aus den Roh-Stats eines
/// Spieltags, den Kadern, Aufstellungen und dem Punkteschema werden die
/// „Sleeper-Awards" berechnet (Team der Woche, MVP, Bank-Held, knappster
/// Sieg, Klatsche, vergeigte Bank, Griff ins Klo). Keine UI-Abhängigkeiten,
/// damit unit-testbar — die Wertung selbst kommt aus dem [fantasy_scoring_engine].
library;

import '../models/fantasy_models.dart';
import 'fantasy_scoring_engine.dart';
import '../../../core/logic/round_robin.dart';

/// Punkte eines Managers an einem Spieltag (effektive Startelf).
class ManagerScore {
  const ManagerScore(this.managerId, this.points);

  final String managerId;
  final int points;
}

/// Ein entschiedenes Head-to-Head (kein Unentschieden, kein Bye).
class RecapMatchup {
  const RecapMatchup({
    required this.winnerId,
    required this.loserId,
    required this.winnerPoints,
    required this.loserPoints,
  });

  final String winnerId;
  final String loserId;
  final int winnerPoints;
  final int loserPoints;

  int get margin => winnerPoints - loserPoints;
}

/// Ein einzelner Spieler als Award-Träger (MVP bzw. Bank-Held).
class PlayerAward {
  const PlayerAward({
    required this.playerId,
    required this.managerId,
    required this.points,
  });

  final String playerId;

  /// Besitzer des Spielers (für „… aus dem Kader von X").
  final String managerId;
  final int points;
}

/// Auf der Bank liegengelassene Punkte: die punktbeste gültige Elf hätte
/// [pointsLeft] mehr gebracht als die tatsächlich gewertete Aufstellung.
class BenchBlunder {
  const BenchBlunder({required this.managerId, required this.pointsLeft});

  final String managerId;
  final int pointsLeft;
}

/// Gebündeltes Recap eines Spieltags. Einzelne Awards sind `null`, wenn es
/// dafür (noch) keine Daten gibt (z. B. keine gewerteten Punkte).
class WeeklyRecap {
  const WeeklyRecap({
    required this.round,
    required this.ranking,
    this.topScore,
    this.lowScore,
    this.closestWin,
    this.blowout,
    this.mvp,
    this.benchHero,
    this.benchBlunder,
  });

  final int round;

  /// Alle Manager nach effektiven Punkten (absteigend, stabil nach ID).
  final List<ManagerScore> ranking;

  /// Höchstes/niedrigstes Wochenergebnis. [lowScore] erst ab zwei Managern.
  final ManagerScore? topScore;
  final ManagerScore? lowScore;

  /// Knappster bzw. deutlichster Sieg des Spieltags.
  final RecapMatchup? closestWin;
  final RecapMatchup? blowout;

  /// Bester Starter (MVP) und bester Bankspieler des Spieltags.
  final PlayerAward? mvp;
  final PlayerAward? benchHero;

  /// Größte auf der Bank liegengelassene Punktzahl (nur wenn > 0).
  final BenchBlunder? benchBlunder;

  /// Gibt es überhaupt etwas zu zeigen (gewertete Punkte)?
  bool get hasData =>
      ranking.any((s) => s.points != 0) || mvp != null || benchHero != null;
}

/// Berechnet das [WeeklyRecap] für [round]. [ids] ist die stabile
/// Manager-Reihenfolge (wie im MatchUp-Tab) — sie bestimmt die Paarungen.
WeeklyRecap computeWeeklyRecap({
  required int round,
  required List<String> ids,
  required List<RosterEntry> roster,
  required Map<String, FantasyPlayer> playerById,
  required List<FantasyLineup> lineups,
  required Map<String, PlayerMatchStats> stats,
  required FantasyScoring scoring,
  required RosterConfig rosterConfig,
}) {
  // Kader je Manager (nur Spieler, die im Pool bekannt sind).
  final rosterByManager = <String, List<FantasyPlayer>>{};
  for (final r in roster) {
    final p = playerById[r.playerId];
    if (p == null) continue;
    rosterByManager.putIfAbsent(r.managerId, () => []).add(p);
  }

  final scores = <ManagerScore>[];
  PlayerAward? mvp; // bester Starter
  PlayerAward? benchHero; // bester Bankspieler
  BenchBlunder? blunder;

  for (final managerId in ids) {
    final players = rosterByManager[managerId] ?? const <FantasyPlayer>[];
    final points = {
      for (final p in players)
        p: scorePlayer(
            stats[p.id] ?? const PlayerMatchStats(), p.position, scoring)
    };

    // Manuelle Aufstellung dieses Spieltags, falls vorhanden.
    Set<String>? manual;
    for (final l in lineups) {
      if (l.round == round && l.managerId == managerId) {
        manual = l.playerIds;
        break;
      }
    }
    final effective = effectiveLineup(points, rosterConfig, manual);
    final best = bestEleven(points, rosterConfig);
    scores.add(ManagerScore(managerId, effective.total));

    // Auf der Bank liegengelassene Punkte (nur bei suboptimaler Aufstellung).
    final left = best.total - effective.total;
    final curBlunder = blunder;
    if (left > 0 && (curBlunder == null || left > curBlunder.pointsLeft)) {
      blunder = BenchBlunder(managerId: managerId, pointsLeft: left);
    }

    // MVP (bester Starter) und Bank-Held (bester Nicht-Starter).
    for (final entry in points.entries) {
      final player = entry.key;
      final pts = entry.value;
      if (pts <= 0) continue;
      if (effective.starterIds.contains(player.id)) {
        final cur = mvp;
        if (cur == null ||
            pts > cur.points ||
            (pts == cur.points && player.id.compareTo(cur.playerId) < 0)) {
          mvp = PlayerAward(
              playerId: player.id, managerId: managerId, points: pts);
        }
      } else {
        final cur = benchHero;
        if (cur == null ||
            pts > cur.points ||
            (pts == cur.points && player.id.compareTo(cur.playerId) < 0)) {
          benchHero = PlayerAward(
              playerId: player.id, managerId: managerId, points: pts);
        }
      }
    }
  }

  // Ranking absteigend, Gleichstand deterministisch nach Manager-ID.
  scores.sort((a, b) => a.points != b.points
      ? b.points.compareTo(a.points)
      : a.managerId.compareTo(b.managerId));

  final topScore = scores.isNotEmpty ? scores.first : null;
  final lowScore = scores.length >= 2 ? scores.last : null;

  // Knappster/deutlichster Sieg aus den Paarungen dieses Spieltags.
  final pointsById = {for (final s in scores) s.managerId: s.points};
  RecapMatchup? closest;
  RecapMatchup? blowout;
  for (final m in roundPairings(ids, round)) {
    if (m.isBye) continue;
    final hp = pointsById[m.home] ?? 0;
    final ap = pointsById[m.away] ?? 0;
    if (hp == ap) continue; // Unentschieden hat keinen Sieger
    final homeWon = hp > ap;
    final res = RecapMatchup(
      winnerId: homeWon ? m.home : m.away!,
      loserId: homeWon ? m.away! : m.home,
      winnerPoints: homeWon ? hp : ap,
      loserPoints: homeWon ? ap : hp,
    );
    final c = closest;
    if (c == null || res.margin < c.margin) closest = res;
    final b = blowout;
    if (b == null || res.margin > b.margin) blowout = res;
  }

  return WeeklyRecap(
    round: round,
    ranking: scores,
    topScore: topScore,
    lowScore: lowScore,
    closestWin: closest,
    blowout: blowout,
    mvp: mvp,
    benchHero: benchHero,
    benchBlunder: blunder,
  );
}
