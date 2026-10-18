import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/saison_punkte.dart';
import 'package:matchup/features/fantasy/logic/spieler_schnitt.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// Der Schnitt zählt nur Spieltage mit Einsatz (auf Ansage, 16.10.2026 —
/// gemeldet an Eric Martel: zwei Einsätze, Schnitt über alle Spieltage).
void main() {
  const regeln = FantasyScoringRules();
  const einsatz = PlayerMatchStats(minutes: 90, goals: 1, played: true);
  const nurKader = PlayerMatchStats(minutes: 0, played: true);
  const anderer = PlayerMatchStats(minutes: 90, played: true);

  // Sechs gewertete Spieltage, an zweien hat „m" gespielt, an einem saß er
  // nur auf der Bank, an dreien stand er gar nicht im Spieltagskader.
  final saison = <int, Map<String, PlayerMatchStats>>{
    1: {'m': einsatz, 'x': anderer},
    2: {'m': nurKader, 'x': anderer},
    3: {'x': anderer},
    4: {'m': einsatz, 'x': anderer},
    5: {'x': anderer},
    6: {'x': anderer},
  };
  final jeSpiel = scorePlayer(einsatz, PlayerPosition.mid, regeln);

  test('der Schnitt teilt durch die Einsätze, nicht durch die Spieltage', () {
    final s = spielerSchnitt(
      saison: saison,
      spielerId: 'm',
      position: PlayerPosition.mid,
      regeln: regeln,
    );
    expect(s.einsaetze, 2, reason: 'nur im Kader ist kein Einsatz');
    expect(s.schnitt, closeTo(jeSpiel, 1e-9));
    expect(s.spieltage, 6);
  });

  test('ohne Einsatz kein Schnitt', () {
    final s = spielerSchnitt(
      saison: {
        1: {'m': nurKader, 'x': anderer},
      },
      spielerId: 'm',
      position: PlayerPosition.mid,
      regeln: regeln,
    );
    expect(s.punkteJeEinsatz, isNull);
    expect(s.schnitt, 0);
  });

  test('die Spielerliste zählt dieselben Einsätze', () {
    final n = einsaetzeJeSpieler(saison);
    expect(n['m'], 2);
    expect(n['x'], 6);
  });
}
