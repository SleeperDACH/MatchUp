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
    // 31*10 + 36*15 + 5*10 + 1*(-4) = 310 + 540 + 50 - 4 = 896
    expect(projectedSeasonPoints(t, PlayerPosition.fwd, scoring), 896);
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
    // 30*10 + 2*15 + 3*10 + 12*12 + 4*(-4) + 1*(-10)
    // = 300 + 30 + 30 + 144 - 16 - 10 = 478
    expect(projectedSeasonPoints(t, PlayerPosition.def, scoring), 478);
  });

  test('Torwart: Zu-Null zählt', () {
    const t = SeasonTotals(appearances: 34, cleanSheets: 14);
    // 34*10 + 14*12 = 340 + 168 = 508
    expect(projectedSeasonPoints(t, PlayerPosition.gk, scoring), 508);
  });

  test('Mittelfeld: Zu Null zählt jetzt mit 4', () {
    // **Neu.** Vorher ging das Mittelfeld hier leer aus; seit der Anpassung
    // bekommt es 4 je Null hinten (Abwehr und Torwart weiter 12).
    const t =
        SeasonTotals(goals: 4, assists: 8, appearances: 28, cleanSheets: 9);
    // 28*10 + 4*15 + 8*10 + 9*4 = 280 + 60 + 80 + 36 = 456
    expect(projectedSeasonPoints(t, PlayerPosition.mid, scoring), 456);
  });

  test('leere Totals ⇒ 0 Punkte', () {
    expect(projectedSeasonPoints(const SeasonTotals(), PlayerPosition.fwd, scoring),
        0);
  });
}
