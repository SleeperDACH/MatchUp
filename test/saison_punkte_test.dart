import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/saison_punkte.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

FantasyPlayer _p(String id, String name, [PlayerPosition pos = PlayerPosition.mid]) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: 'FC Test',
      birthDate: DateTime(1998),
      nationality: 'DE',
    );

void main() {
  const regeln = FantasyScoringRules();

  test('Saisonpunkte summieren über alle Spieltage', () {
    final spieler = {for (final p in [_p('a', 'A'), _p('b', 'B')]) p.id: p};
    final saison = {
      1: {'a': const PlayerMatchStats(minutes: 90, played: true, goals: 1)},
      2: {
        'a': const PlayerMatchStats(minutes: 90, played: true, goals: 1),
        'b': const PlayerMatchStats(minutes: 90, played: true, assists: 1),
      },
    };

    final punkte = saisonPunkte(
        saison: saison, spieler: spieler, regeln: regeln);

    final einTor = scorePlayer(
        const PlayerMatchStats(minutes: 90, played: true, goals: 1),
        PlayerPosition.mid,
        regeln);
    expect(punkte['a'], einTor * 2, reason: 'Zwei Spieltage, zweimal gewertet');
    expect(punkte['b'], isNotNull);
  });

  test('Ein Spieler ohne Einsatz steht nicht in der Karte', () {
    // **Kein Eintrag ist etwas anderes als null Punkte.** Wer nie gespielt
    // hat, bekommt in der Liste keine Zahl hingeschrieben — „0" wäre eine
    // Behauptung über jemanden, der gar nicht auf dem Platz stand.
    final spieler = {for (final p in [_p('a', 'A'), _p('x', 'X')]) p.id: p};
    final punkte = saisonPunkte(
      saison: {
        1: {'a': const PlayerMatchStats(minutes: 90, played: true)}
      },
      spieler: spieler,
      regeln: regeln,
    );
    expect(punkte.containsKey('x'), isFalse);
  });

  test('Ein fremder Spieler in den Stats stört nicht', () {
    // Der Statistik-Datensatz deckt die ganze Liga ab, der Pool nur unsere
    // Spieler. Ein Treffer ohne passenden Spieler wird übersprungen, statt
    // die Summe mit einer geratenen Position zu verfälschen.
    final punkte = saisonPunkte(
      saison: {
        1: {'fremd': const PlayerMatchStats(minutes: 90, played: true, goals: 3)}
      },
      spieler: {'a': _p('a', 'A')},
      regeln: regeln,
    );
    expect(punkte, isEmpty);
  });

  group('freieZuerst', () {
    final frei1 = _p('f1', 'Frei Eins');
    final frei2 = _p('f2', 'Frei Zwei');
    final kader1 = _p('k1', 'Kader Eins');
    final kader2 = _p('k2', 'Kader Zwei');
    final alle = [kader1, frei1, kader2, frei2];

    test('freie Spieler stehen oben, auch wenn sie schlechter sind', () {
      final sortiert = freieZuerst(
        alle,
        inKadern: {'k1', 'k2'},
        punkte: {'k1': 500, 'k2': 400, 'f1': 10, 'f2': 20},
      );
      expect(sortiert.map((p) => p.id).toList(), ['f2', 'f1', 'k1', 'k2'],
          reason: 'Erst die Gruppe, dann die Punkte — der beste Spieler der '
              'Liga steht nicht oben, wenn er nicht zu haben ist');
    });

    test('ohne Punkte entscheidet der Name, und zwar stabil', () {
      final sortiert = freieZuerst(alle, inKadern: const {}, punkte: const {});
      expect(sortiert.map((p) => p.name).toList(),
          ['Frei Eins', 'Frei Zwei', 'Kader Eins', 'Kader Zwei']);
    });

    test('die Eingabeliste bleibt unangetastet', () {
      final vorher = [...alle];
      freieZuerst(alle, inKadern: {'k1'}, punkte: {'f1': 5});
      expect(alle, vorher);
    });
  });
}
