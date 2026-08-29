import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// Genaue Pässe (`accurate-passes`) werden über **positionsabhängige
/// Schwellen** bepunktet. Die Zahlen sind an echten Partien gemessen, nicht
/// gesetzt: Mittelwerte lagen bei TW 25, ABW 34, MF 28, ST 14 — ein Stürmer
/// mit dreißig genauen Pässen ist herausragend, ein Verteidiger mit dreißig
/// unterdurchschnittlich.
void main() {
  const regeln = FantasyScoringRules();

  double punkte(int paesse, PlayerPosition pos) => scorePlayer(
        PlayerMatchStats(minutes: 90, played: true, accuratePasses: paesse),
        pos,
        regeln,
      );

  /// **Nur der Zuwachs durch die Pässe.**
  ///
  /// Die Gesamtsumme taugt nicht als Erwartung: Ein Verteidiger mit 90 Minuten
  /// und null Gegentoren bekommt die Null hinten mit dazu (+12). Der erste
  /// Anlauf dieses Tests prüfte auf 10 und scheiterte an 22 — die Wertung war
  /// richtig, die Annahme falsch.
  double bonus(int paesse, PlayerPosition pos) =>
      punkte(paesse, pos) - punkte(0, pos);

  group('Pass-Boni', () {
    test('unter der ersten Schwelle gibt es nichts', () {
      expect(bonus(19, PlayerPosition.fwd), 0);
      expect(bonus(44, PlayerPosition.def), 0);
    });

    test('die Schwellen zählen zusammen', () {
      // Stürmer: ab 20 und ab 30, je +3.
      expect(bonus(20, PlayerPosition.fwd), 3);
      expect(bonus(29, PlayerPosition.fwd), 3);
      expect(bonus(30, PlayerPosition.fwd), 6);
      expect(bonus(80, PlayerPosition.fwd), 6);
    });

    test('dieselbe Zahl wiegt je Position verschieden', () {
      // Dreißig genaue Pässe: beim Stürmer beide Boni, beim Verteidiger keiner.
      expect(bonus(30, PlayerPosition.fwd), 6);
      expect(bonus(30, PlayerPosition.def), 0);
      // Und ein Verteidiger braucht siebzig für dasselbe.
      expect(bonus(70, PlayerPosition.def), 6);
    });

    test('die Aufschlüsselung nennt den Bonus beim Namen', () {
      final s = scorePlayerDetailed(
        const PlayerMatchStats(minutes: 90, played: true, accuratePasses: 41),
        PlayerPosition.mid,
        regeln,
      );
      expect(
        s.breakdown.map((l) => l.label),
        contains('Pass-Meilenstein (≥40)'),
      );
    });

    test('ohne Pässe bleibt alles wie vorher', () {
      // Damit die Ergänzung keine bestehende Wertung verschiebt.
      const ohne = PlayerMatchStats(minutes: 90, played: true, goals: 1);
      expect(scorePlayer(ohne, PlayerPosition.fwd, regeln), 10 + 16);
    });
  });
}
