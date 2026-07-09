import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/tippspiel/logic/tip_scoring.dart';
import 'package:meine_app/features/tippspiel/models/tip.dart';

void main() {
  group('oddsBonus (konfigurierbare Stufen)', () {
    // Standard: ab Quote 3.0 → +1, ab Quote 5.0 → +5.
    const rules = ScoringRules.kicktippDefault;

    // Heimsieg-Quoten: krasser Außenseiter daheim (6.0), Favorit auswärts (1.4).
    const homeUnderdog = {'home': 6.0, 'draw': 4.2, 'away': 1.4};

    int bonusFor(Map<String, double> o, int th, int ta, int rh, int ra,
            {ScoringRules r = rules}) =>
        oddsBonus(
          tipHome: th,
          tipAway: ta,
          resultHome: rh,
          resultAway: ra,
          homeWin: o['home'],
          draw: o['draw'],
          awayWin: o['away'],
          rules: r,
        );

    test('kein Bonus ohne richtige Tendenz (falscher Sieger getippt)', () {
      expect(bonusFor(homeUnderdog, 2, 1, 1, 2), 0);
    });

    test('höhere Stufe: Quote ≥ 5.0 → +5', () {
      expect(bonusFor(homeUnderdog, 1, 0, 2, 1), 5);
    });

    test('höhere Stufe greift auch bei exaktem Tipp', () {
      expect(bonusFor(homeUnderdog, 3, 0, 3, 0), 5);
    });

    test('kein Bonus, wenn der Favorit gewinnt (Quote < 3.0)', () {
      expect(bonusFor(homeUnderdog, 0, 1, 0, 2), 0);
    });

    test('untere Stufe: Quote zwischen 3.0 und 5.0 → +1', () {
      const o = {'home': 1.7, 'draw': 3.5, 'away': 3.8};
      expect(bonusFor(o, 0, 1, 1, 2), 1);
    });

    test('kein Bonus unter der ersten Stufe (Quote < 3.0)', () {
      const o = {'home': 2.2, 'draw': 3.2, 'away': 2.5};
      expect(bonusFor(o, 0, 1, 0, 1), 0);
    });

    test('Stufen stapeln nicht: Quote ≥ 5.0 gibt +5, nicht +6', () {
      const o = {'home': 1.5, 'draw': 4.0, 'away': 6.5};
      expect(bonusFor(o, 0, 1, 0, 1), 5);
    });

    test('Unentschieden zählt mit der X-Quote (≥ 5.0 → +5)', () {
      const o = {'home': 1.6, 'draw': 5.5, 'away': 4.0};
      expect(bonusFor(o, 1, 1, 1, 1), 5);
    });

    test('Remis mit moderater X-Quote (3.0–5.0) → +1', () {
      const o = {'home': 1.5, 'draw': 3.6, 'away': 6.0};
      expect(bonusFor(o, 0, 0, 0, 0), 1);
    });

    test('Grenzfall: Quote genau 5.0 → +5 (inklusiv)', () {
      const o = {'home': 5.0, 'draw': 4.0, 'away': 1.6};
      expect(bonusFor(o, 1, 0, 1, 0), 5);
    });

    test('Grenzfall: Quote genau 3.0 → +1 (inklusiv)', () {
      const o = {'home': 1.5, 'draw': 3.4, 'away': 3.0};
      expect(bonusFor(o, 0, 1, 0, 1), 1);
    });

    test('kein Bonus ohne eingefrorene Quote (null)', () {
      expect(
        oddsBonus(
          tipHome: 2,
          tipAway: 1,
          resultHome: 2,
          resultAway: 1,
          homeWin: null,
          draw: null,
          awayWin: null,
          rules: rules,
        ),
        0,
      );
    });

    test('eigene Konfiguration: ab 4.0 → +2, ab 8.0 → +10', () {
      const r = ScoringRules(
          oddsOdds1: 4.0, oddsPoints1: 2, oddsOdds2: 8.0, oddsPoints2: 10);
      // Quote 6.0 liegt zwischen 4.0 und 8.0 → untere Stufe +2.
      expect(bonusFor(homeUnderdog, 1, 0, 2, 1, r: r), 2);
      // Quote 9.0 ≥ 8.0 → +10.
      const krass = {'home': 9.0, 'draw': 5.0, 'away': 1.3};
      expect(bonusFor(krass, 1, 0, 2, 1, r: r), 10);
    });
  });
}
