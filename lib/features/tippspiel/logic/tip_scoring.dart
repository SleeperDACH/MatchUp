import '../models/tip.dart';

/// Pure Scoring-Engine für das Tippspiel — bewusst ohne Abhängigkeiten,
/// damit sie identisch im Client (Anzeige) und später in einer Supabase
/// Edge Function (verbindliche Wertung) nachgebaut werden kann.
///
/// Wertungslogik (Kicktipp-Standard):
/// - exaktes Ergebnis getroffen → [ScoringRules.exact]
/// - richtige Tordifferenz (bei Unentschieden: Unentschieden getippt,
///   aber falsches Ergebnis) → [ScoringRules.goalDiff]
/// - nur richtige Tendenz (Sieger korrekt) → [ScoringRules.tendency]
/// - sonst 0 Punkte
int scoreTip({
  required int tipHome,
  required int tipAway,
  required int resultHome,
  required int resultAway,
  ScoringRules rules = ScoringRules.kicktippDefault,
}) {
  if (tipHome == resultHome && tipAway == resultAway) {
    return rules.exact;
  }
  if (tipHome - tipAway == resultHome - resultAway) {
    return rules.goalDiff;
  }
  if ((tipHome - tipAway).sign == (resultHome - resultAway).sign) {
    return rules.tendency;
  }
  return 0;
}

/// Quoten-Bonus für mutige, richtige Tipps — kommt **on top** der
/// Basispunkte aus [scoreTip] und lässt diese unverändert.
///
/// Voraussetzung ist die richtige Tendenz (Sieger bzw. Unentschieden korrekt
/// getippt) — bewusst über den `sign`-Vergleich geprüft, identisch zur
/// SQL-View `tip_round_standings`. Maßgeblich ist die zum Anstoß
/// eingefrorene Quote des tatsächlich eingetretenen Ausgangs
/// (Heimsieg → [homeWin], Unentschieden → [draw], Auswärtssieg → [awayWin]):
/// - Quote > 5.0 → +5 Punkte (krasser Außenseiter)
/// - sonst Quote ≥ 2.0 über dem Favoriten (niedrigste der drei Quoten) → +1
/// - sonst 0
///
/// Die beiden Stufen stapeln nicht — der >5.0-Fall liefert ohnehin den
/// höheren Bonus. Ohne eingefrorene Quoten (`null`) gibt es keinen Bonus.
int oddsBonus({
  required int tipHome,
  required int tipAway,
  required int resultHome,
  required int resultAway,
  required double? homeWin,
  required double? draw,
  required double? awayWin,
}) {
  // Tendenz korrekt? (Sieger bzw. Remis richtig getippt)
  if ((tipHome - tipAway).sign != (resultHome - resultAway).sign) return 0;
  if (homeWin == null || draw == null || awayWin == null) return 0;

  final outcomeOdds = resultHome > resultAway
      ? homeWin
      : resultHome < resultAway
          ? awayWin
          : draw;
  final favorite = [homeWin, draw, awayWin].reduce((a, b) => a < b ? a : b);

  if (outcomeOdds > 5.0) return 5;
  if (outcomeOdds - favorite >= 2.0) return 1;
  return 0;
}
