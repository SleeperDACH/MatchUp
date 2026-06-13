import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/tippspiel/logic/tip_scoring.dart';

void main() {
  group('oddsBonus', () {
    // Heimsieg-Quoten: krasser Außenseiter daheim (6.0), Favorit auswärts (1.4).
    const homeUnderdog = {'home': 6.0, 'draw': 4.2, 'away': 1.4};
    // th/ta = Tipp, rh/ra = Ergebnis.
    int bonusFor(Map<String, double> o, int th, int ta, int rh, int ra) =>
        oddsBonus(
          tipHome: th,
          tipAway: ta,
          resultHome: rh,
          resultAway: ra,
          homeWin: o['home'],
          draw: o['draw'],
          awayWin: o['away'],
        );

    test('kein Bonus ohne richtige Tendenz (falscher Sieger getippt)', () {
      // Heimsieg getippt (2:1), aber Auswärtssieg (1:2) eingetreten.
      expect(bonusFor(homeUnderdog, 2, 1, 1, 2), 0);
    });

    test('+5 für richtigen Außenseiter-Sieg mit Quote > 5.0', () {
      // Heimsieg richtig getippt, Heim-Quote 6.0 (> 5.0).
      expect(bonusFor(homeUnderdog, 1, 0, 2, 1), 5);
    });

    test('+5 greift auch bei exaktem Tipp', () {
      expect(bonusFor(homeUnderdog, 3, 0, 3, 0), 5);
    });

    test('kein Bonus, wenn der Favorit gewinnt', () {
      // Auswärtssieg richtig getippt, Away-Quote 1.4 → kein Bonus.
      expect(bonusFor(homeUnderdog, 0, 1, 0, 2), 0);
    });

    test('+1 für moderaten Außenseiter (Differenz ≥ 2.0, Quote ≤ 5.0)', () {
      // Away gewinnt mit Quote 3.8; Favorit ist Home (1.7) → Diff 2.1 ≥ 2.0.
      const o = {'home': 1.7, 'draw': 3.5, 'away': 3.8};
      expect(bonusFor(o, 0, 1, 1, 2), 1);
    });

    test('kein Bonus bei klarem Favoriten-Umfeld (Diff < 2.0, Quote ≤ 5.0)', () {
      // Away gewinnt mit Quote 3.0; Favorit Home 2.2 → Diff 0.8 < 2.0.
      const o = {'home': 2.2, 'draw': 3.2, 'away': 3.0};
      expect(bonusFor(o, 0, 1, 0, 1), 0);
    });

    test('Stufen stapeln nicht: Quote > 5.0 gibt +5, nicht +6', () {
      // Away-Quote 6.5 > 5.0 und auch ≥ 2.0 über Favorit (1.5) → nur +5.
      const o = {'home': 1.5, 'draw': 4.0, 'away': 6.5};
      expect(bonusFor(o, 0, 1, 0, 1), 5);
    });

    test('Unentschieden zählt mit der X-Quote', () {
      // Remis richtig getippt, X-Quote 5.5 > 5.0 → +5.
      const o = {'home': 1.6, 'draw': 5.5, 'away': 4.0};
      expect(bonusFor(o, 1, 1, 1, 1), 5);
    });

    test('Remis mit moderater X-Quote: +1 bei Differenz ≥ 2.0', () {
      // Remis 0:0, X-Quote 3.6; Favorit Home 1.5 → Diff 2.1 ≥ 2.0 → +1.
      const o = {'home': 1.5, 'draw': 3.6, 'away': 6.0};
      expect(bonusFor(o, 0, 0, 0, 0), 1);
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
        ),
        0,
      );
    });

    test('Grenzfall: Quote genau 5.0 gibt nicht +5 (nur > 5.0)', () {
      // Home-Quote 5.0; Favorit away 1.6 → Diff 3.4 ≥ 2.0 → fällt auf +1.
      const o = {'home': 5.0, 'draw': 4.0, 'away': 1.6};
      expect(bonusFor(o, 1, 0, 1, 0), 1);
    });

    test('Grenzfall: Differenz genau 2.0 gibt +1', () {
      // Away-Quote 3.5; Favorit home 1.5 → Diff exakt 2.0 → +1.
      const o = {'home': 1.5, 'draw': 3.4, 'away': 3.5};
      expect(bonusFor(o, 0, 1, 0, 1), 1);
    });
  });
}
