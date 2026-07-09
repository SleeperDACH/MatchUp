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
/// (Heimsieg → [homeWin], Unentschieden → [draw], Auswärtssieg → [awayWin]).
///
/// Zwei **konfigurierbare** Stufen (aus [rules]):
/// - ab Quote [ScoringRules.oddsOdds2] → [ScoringRules.oddsPoints2] (höhere
///   Stufe, krasser Außenseiter)
/// - sonst ab Quote [ScoringRules.oddsOdds1] → [ScoringRules.oddsPoints1]
/// - sonst 0
///
/// Die Stufen stapeln nicht — die höhere gewinnt. Ohne eingefrorene Quoten
/// (`null`) gibt es keinen Bonus.
int oddsBonus({
  required int tipHome,
  required int tipAway,
  required int resultHome,
  required int resultAway,
  required double? homeWin,
  required double? draw,
  required double? awayWin,
  required ScoringRules rules,
}) {
  // Tendenz korrekt? (Sieger bzw. Remis richtig getippt)
  if ((tipHome - tipAway).sign != (resultHome - resultAway).sign) return 0;
  if (homeWin == null || draw == null || awayWin == null) return 0;

  final outcomeOdds = resultHome > resultAway
      ? homeWin
      : resultHome < resultAway
          ? awayWin
          : draw;

  if (outcomeOdds >= rules.oddsOdds2) return rules.oddsPoints2;
  if (outcomeOdds >= rules.oddsOdds1) return rules.oddsPoints1;
  return 0;
}

/// Alleinstellungs-Bonus: kommt **on top** der Basispunkte, wenn ein exaktes
/// Ergebnis von genau **einem** Mitglied getroffen wurde. [isExact] muss der
/// exakte Treffer sein, [exactHittersOnFixture] die Anzahl der Mitglieder, die
/// dieses Spiel exakt getippt haben. Trifft nur eine/r → [points], sonst 0.
///
/// Identisch zur SQL-View `tip_round_standings` (Window-Count je Spiel) — bei
/// Änderungen beide anpassen.
int soloBonus({
  required bool isExact,
  required int exactHittersOnFixture,
  required int points,
}) =>
    (isExact && exactHittersOnFixture == 1) ? points : 0;
