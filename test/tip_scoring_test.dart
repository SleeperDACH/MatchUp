import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/tippspiel/logic/tip_scoring.dart';
import 'package:meine_app/features/tippspiel/models/tip.dart';

void main() {
  group('scoreTip (Kicktipp-Standard: exakt 4, Differenz 3, Tendenz 2)', () {
    int score(int th, int ta, int rh, int ra) => scoreTip(
        tipHome: th, tipAway: ta, resultHome: rh, resultAway: ra);

    test('exaktes Ergebnis gibt 4 Punkte', () {
      expect(score(2, 1, 2, 1), 4);
      expect(score(0, 0, 0, 0), 4);
    });

    test('richtige Tordifferenz gibt 3 Punkte', () {
      expect(score(2, 1, 3, 2), 3);
      expect(score(1, 3, 0, 2), 3);
    });

    test('Unentschieden getippt und gespielt, aber falsches Ergebnis, gibt 3',
        () {
      expect(score(1, 1, 2, 2), 3);
    });

    test('nur richtige Tendenz gibt 2 Punkte', () {
      expect(score(1, 0, 4, 2), 2);
      expect(score(0, 1, 1, 3), 2);
    });

    test('falsche Tendenz gibt 0 Punkte (Standard)', () {
      expect(score(2, 1, 1, 2), 0);
      expect(score(1, 1, 2, 0), 0);
      expect(score(0, 2, 0, 0), 0);
    });

    test('Strafpunkte für falschen Tipp (wrongTip)', () {
      const rules = ScoringRules(wrongTip: -3);
      int s(int th, int ta, int rh, int ra) => scoreTip(
          tipHome: th, tipAway: ta, resultHome: rh, resultAway: ra,
          rules: rules);
      // Komplett falsch → Strafe.
      expect(s(2, 1, 1, 2), -3);
      expect(s(1, 1, 2, 0), -3);
      // Treffer/Tendenz bleiben unverändert positiv.
      expect(s(1, 0, 1, 0), 4); // exakt
      expect(s(2, 0, 1, 0), 2); // Tendenz
    });

    test('eigene Regeln werden angewendet', () {
      const rules = ScoringRules(exact: 10, goalDiff: 5, tendency: 1);
      expect(score(1, 0, 1, 0), 4); // Standard unverändert
      expect(
          scoreTip(
              tipHome: 1,
              tipAway: 0,
              resultHome: 1,
              resultAway: 0,
              rules: rules),
          10);
      expect(
          scoreTip(
              tipHome: 1,
              tipAway: 0,
              resultHome: 2,
              resultAway: 1,
              rules: rules),
          5);
      expect(
          scoreTip(
              tipHome: 1,
              tipAway: 0,
              resultHome: 3,
              resultAway: 1,
              rules: rules),
          1);
    });
  });
}
