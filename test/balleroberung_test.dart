import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Balleroberung und abgefangener Ball sind zwei Dinge.**
///
/// Die App nannte `interceptions` lange „Balleroberung" — gemessen an vier
/// Partien (84 Spieler ab 60 Minuten) sind das aber verschiedene Felder:
/// `interceptions` im Schnitt 0,8 je Spieler, `ball-recovery` 2,9, und bei 56
/// von 84 Spielern unterschiedlich. Aufgefallen ist es an einem Spieler, bei
/// dem beide zufällig 1 waren — die Zahl stimmte, der Name nicht.
void main() {
  const regeln = FantasyScoringRules();

  double punkte(PlayerMatchStats s) =>
      scorePlayer(s, PlayerPosition.mid, regeln);

  test('beide Felder zählen, und zwar verschieden', () {
    const nur = PlayerMatchStats(minutes: 90, played: true);
    const abgefangen =
        PlayerMatchStats(minutes: 90, played: true, interceptions: 5);
    const erobert =
        PlayerMatchStats(minutes: 90, played: true, ballRecovery: 5);
    // Abgefangener Ball: 1 je Stück. Balleroberung: 0,4 — häufiger, einzeln
    // weniger wert.
    expect(punkte(abgefangen) - punkte(nur), 5);
    expect(punkte(erobert) - punkte(nur), closeTo(2, 0.001));
  });

  test('die Aufschlüsselung nennt beide getrennt', () {
    final s = scorePlayerDetailed(
      const PlayerMatchStats(
          minutes: 90, played: true, interceptions: 2, ballRecovery: 6),
      PlayerPosition.def,
      regeln,
    );
    final labels = s.breakdown.map((l) => l.label).toList();
    expect(labels, contains('Abgefangener Ball'));
    expect(labels, contains('Balleroberung'));
  });

  test('Balleroberungen zählen NICHT in den Defensiv-Meilenstein', () {
    // Die Schwellen sind ohne dieses Feld geeicht. Mit ihm spränge der Median
    // beim Torwart von 0 auf 8 — direkt an die erste Schwelle von 9.
    const viele =
        PlayerMatchStats(minutes: 90, played: true, ballRecovery: 14);
    final s = scorePlayerDetailed(viele, PlayerPosition.gk, regeln);
    expect(
      s.breakdown.where((l) => l.label.startsWith('Defensiv-Meilenstein')),
      isEmpty,
    );
  });
}
