import '../../../core/data/odds/frozen_odds.dart';
import '../../../core/models/models.dart';
import '../models/tip_round.dart';
import 'tip_scoring.dart';

/// Aggregierte Tipp-Bilanz eines Nutzers über alle seine Tipprunden —
/// Grundlage für das Profil-Dashboard.
class TipStats {
  const TipStats({
    this.rounds = 0,
    this.scored = 0,
    this.exact = 0,
    this.goalDiff = 0,
    this.tendency = 0,
    this.points = 0,
    this.bestTip = 0,
  });

  /// Anzahl Tipprunden, in denen der Nutzer Mitglied ist.
  final int rounds;

  /// Gewertete Tipps (auf beendete Spiele).
  final int scored;
  final int exact;
  final int goalDiff;
  final int tendency;

  /// Summe aller Punkte (inkl. Quoten-Bonus) — über alle Runden.
  final int points;

  /// Beste Einzelwertung (Punkte inkl. Bonus) eines einzelnen Tipps.
  final int bestTip;

  static const empty = TipStats();

  int get hits => exact + goalDiff + tendency;
  int get missed => scored - hits;

  /// Trefferquote: Anteil der Tipps mit mindestens richtiger Tendenz.
  double get accuracy => scored == 0 ? 0 : hits / scored;
}

int _sign(int x) => x > 0 ? 1 : (x < 0 ? -1 : 0);

/// Pure Bilanz-Berechnung über die eigenen Tipps. Wertet nur **beendete**
/// Spiele; nutzt dieselbe Formel wie die Tabelle ([scoreTip] + [oddsBonus]).
TipStats computeTipStats({
  required String userId,
  required List<TipRound> rounds,
  required Map<String, List<MemberTip>> tipsByRound,
  required Map<String, Fixture> fixturesById,
  Map<String, FrozenOdds> frozenOdds = const {},
}) {
  var scored = 0, exact = 0, goalDiff = 0, tendency = 0, points = 0, best = 0;
  for (final r in rounds) {
    for (final tip in tipsByRound[r.id] ?? const <MemberTip>[]) {
      if (tip.userId != userId) continue;
      final f = fixturesById[tip.fixtureId];
      if (f == null || !f.hasResult) continue;
      final rh = f.homeScore!, ra = f.awayScore!;
      scored++;
      final fo = frozenOdds[tip.fixtureId];
      // Persönliche Bilanz: Basispunkte + (falls aktiv) Quoten-Bonus. Der
      // Alleinstellungs-Bonus braucht den ligaweiten Vergleich und steckt
      // daher nur in der Tabelle (round_table.dart), nicht in dieser Solo-Sicht.
      final p = scoreTip(
            tipHome: tip.homeGoals,
            tipAway: tip.awayGoals,
            resultHome: rh,
            resultAway: ra,
            rules: r.scoring,
          ) +
          (r.scoring.oddsBonus
              ? oddsBonus(
                  tipHome: tip.homeGoals,
                  tipAway: tip.awayGoals,
                  resultHome: rh,
                  resultAway: ra,
                  homeWin: fo?.homeWin,
                  draw: fo?.draw,
                  awayWin: fo?.awayWin,
                  rules: r.scoring,
                )
              : 0);
      points += p;
      if (p > best) best = p;

      if (tip.homeGoals == rh && tip.awayGoals == ra) {
        exact++;
      } else if (tip.homeGoals - tip.awayGoals == rh - ra) {
        goalDiff++;
      } else if (_sign(tip.homeGoals - tip.awayGoals) == _sign(rh - ra)) {
        tendency++;
      }
    }
  }
  return TipStats(
    rounds: rounds.length,
    scored: scored,
    exact: exact,
    goalDiff: goalDiff,
    tendency: tendency,
    points: points,
    bestTip: best,
  );
}
