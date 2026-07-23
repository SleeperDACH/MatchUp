import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/logic/draft_ranking.dart';
import 'package:meine_app/features/fantasy/models/fantasy_models.dart';

void main() {
  // Standard-Scoring: Einsatz 2, Tor GK/DEF 6 / MID 5 / FWD 4, Assist 3,
  // Zu-Null (GK/DEF) 4, Gelb -1, Rot -3.
  const scoring = FantasyScoring();

  test('Stürmer: Einsätze + Tore + Assists + Karten, keine Zu-Null-Punkte', () {
    const t = SeasonTotals(
      goals: 36,
      assists: 5,
      appearances: 31,
      yellow: 1,
      red: 0,
      cleanSheets: 11, // zählt für Stürmer NICHT
    );
    // 31*2 + 36*4 + 5*3 + 1*(-1) = 62 + 144 + 15 - 1 = 220
    expect(projectedSeasonPoints(t, PlayerPosition.fwd, scoring), 220);
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
    // 30*2 + 2*6 + 3*3 + 12*4 + 4*(-1) + 1*(-3)
    // = 60 + 12 + 9 + 48 - 4 - 3 = 122
    expect(projectedSeasonPoints(t, PlayerPosition.def, scoring), 122);
  });

  test('Torwart: Zu-Null zählt, Positions-Torwert 6', () {
    const t = SeasonTotals(appearances: 34, cleanSheets: 14);
    // 34*2 + 14*4 = 68 + 56 = 124
    expect(projectedSeasonPoints(t, PlayerPosition.gk, scoring), 124);
  });

  test('Mittelfeld: Tore×5, kein Zu-Null-Bonus', () {
    const t = SeasonTotals(goals: 4, assists: 8, appearances: 28, cleanSheets: 9);
    // 28*2 + 4*5 + 8*3 = 56 + 20 + 24 = 100
    expect(projectedSeasonPoints(t, PlayerPosition.mid, scoring), 100);
  });

  test('leere Totals ⇒ 0 Punkte', () {
    expect(projectedSeasonPoints(const SeasonTotals(), PlayerPosition.fwd, scoring),
        0);
  });
}
