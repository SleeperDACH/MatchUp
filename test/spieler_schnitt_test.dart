import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/spieler_schnitt.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Zwei Schnitte, und ihr Unterschied ist die Auskunft.**
///
/// „⌀ je Spieltag" ist der Erwartungswert für die nächste Woche, „⌀ je Einsatz"
/// sagt, was er kann, wenn er spielt. Bei einem Stammspieler sind beide gleich,
/// bei einem Ergänzungsspieler weit auseinander — und genau das will man vor
/// einem Pick-up wissen.
const _voll = PlayerMatchStats(minutes: 90, played: true, goals: 1);
const _kurz = PlayerMatchStats(minutes: 30, played: true);
const _ohne = PlayerMatchStats(minutes: 0);

SpielerSchnitt _schnitt(Map<int, Map<String, PlayerMatchStats>> saison) =>
    spielerSchnitt(
      saison: saison,
      spielerId: 'p',
      position: PlayerPosition.mid,
      regeln: const FantasyScoringRules(),
    );

void main() {
  test('ohne gewertete Spieltage gibt es nichts zu zeigen', () {
    expect(_schnitt(const {}).hatDaten, isFalse);
    // Ein Spieltag, der noch nicht gewertet ist, zählt nicht als Nenner.
    expect(_schnitt(const {1: {}}).hatDaten, isFalse);
  });

  test('ein Stammspieler hat zwei gleiche Zahlen', () {
    final s = _schnitt({
      1: {'p': _voll},
      2: {'p': _voll},
    });
    expect(s.spieltage, 2);
    expect(s.einsaetze, 2);
    expect(s.minutenJeSpieltag, 90);
    expect(s.minutenJeEinsatz, 90);
    expect(s.punkteJeSpieltag, s.punkteJeEinsatz);
  });

  test('ein Nichteinsatz drückt den Spieltags-Schnitt, nicht den je Einsatz',
      () {
    // **Der Kern.** Zwei Spieltage, einmal 90 Minuten, einmal gar nicht.
    final s = _schnitt({
      1: {'p': _voll},
      2: {'p': _ohne},
    });
    expect(s.spieltage, 2);
    expect(s.einsaetze, 1);
    expect(s.minutenJeSpieltag, 45);
    expect(s.minutenJeEinsatz, 90,
        reason: 'Wenn er spielt, spielt er durch');
    expect(s.punkteJeEinsatz, greaterThan(s.punkteJeSpieltag));
  });

  test('wer im Datensatz fehlt, zählt als Null — nicht als „gab es nicht"', () {
    // Ein gewerteter Spieltag ohne seine Zeile heißt: Er war nicht dabei.
    final s = _schnitt({
      1: {'p': _voll},
      2: {'anderer': _voll},
    });
    expect(s.spieltage, 2);
    expect(s.einsaetze, 1);
    expect(s.minutenJeSpieltag, 45);
  });

  test('ohne eine einzige Minute gibt es keinen Einsatz-Schnitt', () {
    // `null` statt 0: Eine 0 wäre eine Aussage über etwas, das nie stattfand.
    final s = _schnitt({
      1: {'p': _ohne},
      2: {'p': _ohne},
    });
    expect(s.spieltage, 2);
    expect(s.einsaetze, 0);
    expect(s.minutenJeEinsatz, isNull);
    expect(s.punkteJeEinsatz, isNull);
    expect(s.punkteJeSpieltag, 0);
  });

  test('Teileinsätze mitteln sich richtig', () {
    final s = _schnitt({
      1: {'p': _voll},
      2: {'p': _kurz},
      3: {'p': _ohne},
    });
    expect(s.spieltage, 3);
    expect(s.einsaetze, 2);
    expect(s.minutenJeSpieltag, closeTo(40, 0.001));
    expect(s.minutenJeEinsatz, closeTo(60, 0.001));
  });
}
