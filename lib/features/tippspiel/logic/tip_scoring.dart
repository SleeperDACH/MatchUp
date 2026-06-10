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
