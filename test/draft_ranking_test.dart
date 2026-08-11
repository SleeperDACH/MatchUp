import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/draft_ranking.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

void main() {
  // Die Näherung nutzt die Standardwertung: Einsatz 10 (höchste Stufe, weil
  // die Saison-Summen keine Minuten je Spiel führen), Tor 16, Vorlage 12,
  // Zu Null GK/DEF 12, Gelb −4, Rot −10.
  const scoring = FantasyScoringRules.standard;

  test('Stürmer: Einsätze + Tore + Assists + Karten, keine Zu-Null-Punkte', () {
    const t = SeasonTotals(
      goals: 36,
      assists: 5,
      appearances: 31,
      yellow: 1,
      red: 0,
      cleanSheets: 11, // zählt für Stürmer NICHT
    );
    // 31*10 + 36*16 + 5*12 + 1*(-4) = 310 + 576 + 60 - 4 = 942
    expect(projectedSeasonPoints(t, PlayerPosition.fwd, scoring), 942);
  });

  test('Abwehr: Tore×6, Zu-Null zählt', () {
    const t = SeasonTotals(
      goals: 2,
      assists: 3,
      appearances: 30,
      cleanSheets: 12,
      yellow: 4,
      red: 1,
    );
    // 30*10 + 2*16 + 3*12 + 12*12 + 4*(-4) + 1*(-10)
    // = 300 + 32 + 36 + 144 - 16 - 10 = 486
    expect(projectedSeasonPoints(t, PlayerPosition.def, scoring), 486);
  });

  test('Torwart: Zu-Null zählt', () {
    const t = SeasonTotals(appearances: 34, cleanSheets: 14);
    // 34*10 + 14*12 = 340 + 168 = 508
    expect(projectedSeasonPoints(t, PlayerPosition.gk, scoring), 508);
  });

  test('Mittelfeld: kein Zu-Null-Bonus', () {
    const t =
        SeasonTotals(goals: 4, assists: 8, appearances: 28, cleanSheets: 9);
    // 28*10 + 4*16 + 8*12 = 280 + 64 + 96 = 440
    expect(projectedSeasonPoints(t, PlayerPosition.mid, scoring), 440);
  });

  test('leere Totals ⇒ 0 Punkte', () {
    expect(projectedSeasonPoints(const SeasonTotals(), PlayerPosition.fwd, scoring),
        0);
  });
}
