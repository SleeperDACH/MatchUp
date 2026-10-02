import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/siegchance.dart';

/// **Die Gewinnwahrscheinlichkeit im MatchUp-Kopf.**
///
/// Geprüft wird hier und nicht am Widget, weil an der Zahl ein Modell hängt:
/// Dieselbe Differenz muss bei ruhiger Liga eine andere Chance ergeben als bei
/// unruhiger. Ein Bild zeigt, wie der Balken aussah — nicht, ob er stimmt.

void main() {
  group('streuung', () {
    test('ohne Historie gibt es nichts zu messen', () {
      expect(streuung(const {}), isNull);
      expect(streuung(const {1: {'a': 90.0}}), isNull,
          reason: 'ein einziger Wert hat keine Abweichung');
    });

    test('gleiche Summen ergeben keine brauchbare Streuung', () {
      // Rechnerisch 0 — damit ließe sich nicht teilen, also null statt 0.
      expect(
        streuung(const {
          1: {'a': 100.0, 'b': 100.0},
          2: {'a': 100.0, 'b': 100.0},
        }),
        isNull,
      );
    });

    test('rechnet die Stichproben-Standardabweichung über alle Summen', () {
      // Werte: 90, 110, 100, 120 → Mittel 105, Abweichungen -15/+5/-5/+15,
      // Quadratsumme 500, geteilt durch n-1 = 3 → 166,67; Wurzel ≈ 12,91.
      final s = streuung(const {
        1: {'a': 90.0, 'b': 110.0},
        2: {'a': 100.0, 'b': 120.0},
      });
      expect(s, isNotNull);
      expect(s!, closeTo(math.sqrt(500 / 3), 0.001));
    });
  });

  group('siegchance', () {
    test('ohne gemessene Streuung gibt es keine Zahl', () {
      expect(siegchance(heim: 200, gast: 100, wochenStreuung: null), isNull);
      expect(siegchance(heim: 200, gast: 100, wochenStreuung: 0), isNull);
    });

    test('gleiche Prognose ist ein Münzwurf', () {
      final p = siegchance(heim: 150, gast: 150, wochenStreuung: 20);
      expect(p, isNotNull);
      expect(p!, closeTo(0.5, 0.0001));
    });

    test('beide Seiten ergänzen sich zu 100 Prozent', () {
      final heim = siegchance(heim: 180, gast: 150, wochenStreuung: 25)!;
      final gast = siegchance(heim: 150, gast: 180, wochenStreuung: 25)!;
      expect(heim + gast, closeTo(1.0, 0.0001));
    });

    test('derselbe Vorsprung wiegt in einer ruhigen Liga schwerer', () {
      // **Der eigentliche Grund für das Modell.** 30 Punkte Vorsprung sind
      // viel, wenn die Wochensummen eng beieinanderliegen — und wenig, wenn
      // sie ohnehin um 60 Punkte schwanken. Ein Punkteanteil könnte das nicht
      // unterscheiden.
      final ruhig = siegchance(heim: 180, gast: 150, wochenStreuung: 10)!;
      final unruhig = siegchance(heim: 180, gast: 150, wochenStreuung: 60)!;
      expect(ruhig, greaterThan(unruhig));
      // Die Grenzen sind **nachgerechnet, nicht gegriffen**: Bei σ=10 ist die
      // Skala 10·√2·√3/π ≈ 7,8 — 30 Punkte Vorsprung sind dann fast vier
      // Skalen und praktisch entschieden. Bei σ=60 ist sie ≈ 46,8, derselbe
      // Vorsprung also gut ein halber Schritt: 0,655, kaum mehr als ein
      // Münzwurf. Genau dieser Unterschied ist der Grund für das Modell.
      expect(ruhig, greaterThan(0.95));
      expect(unruhig, lessThan(0.7));
    });

    test('bleibt in den Grenzen — 0 und 100 Prozent gibt es nicht', () {
      final p = siegchance(heim: 5000, gast: 0, wochenStreuung: 5)!;
      expect(p, lessThanOrEqualTo(0.99));
      final q = siegchance(heim: 0, gast: 5000, wochenStreuung: 5)!;
      expect(q, greaterThanOrEqualTo(0.01));
    });
  });
}
