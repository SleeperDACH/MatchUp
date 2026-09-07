import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/data/abfrage_buendel.dart';

/// **Dieselbe Frage wird nicht mehrfach gestellt.**
///
/// Gemeldet: *„Auch bei guter Internetverbindung sind ganz oft Ladescreens."*
/// Nachgemessen war das keine Langsamkeit, sondern eine Menge: Der komplette
/// Bundesliga-Spielplan (gemessen 137 KB) wird von sechs Stellen unabhängig
/// geholt, drei davon nur, um eine einzige Zahl daraus zu rechnen.
void main() {
  test('sechs Frager im selben Moment, eine Verbindung', () async {
    // Genau der Fall beim Öffnen eines Schirms: `currentRoundProvider`,
    // `availableRoundsProvider`, `roundFixturesProvider`,
    // `seasonFixturesProvider`, `leagueSeasonFixturesProvider` und
    // `fantasySeasonFixturesProvider` fragen alle nach derselben Saison.
    var abrufe = 0;
    final buendel = AbfrageBuendel();
    Future<String> frage() => buendel.hole('seasonFixtures|82', const Duration(seconds: 20), () async {
          abrufe++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'Spielplan';
        });

    final antworten = await Future.wait([for (var i = 0; i < 6; i++) frage()]);

    expect(abrufe, 1, reason: 'eine Verbindung, nicht sechs');
    expect(antworten, everyElement('Spielplan'));
  });

  test('nach Ablauf der Geltung wird wirklich neu gefragt', () async {
    var abrufe = 0;
    final buendel = AbfrageBuendel();
    var jetzt = DateTime(2026, 9, 7, 15);
    buendel.jetzt = () => jetzt;
    Future<int> frage() =>
        buendel.hole('standings|82', const Duration(seconds: 30), () async => ++abrufe);

    expect(await frage(), 1);
    jetzt = jetzt.add(const Duration(seconds: 29));
    expect(await frage(), 1, reason: 'noch gültig');
    jetzt = jetzt.add(const Duration(seconds: 2));
    expect(await frage(), 2, reason: 'abgelaufen — ein laufendes Spiel darf '
        'seinen Stand ändern');
  });

  test('ein Fehler wird nicht gemerkt', () async {
    // Sonst hinge ein Funkloch für die ganze Geltungsdauer fest, und der
    // zweite Versuch wäre so aussichtslos wie der erste.
    var abrufe = 0;
    final buendel = AbfrageBuendel();
    Future<int> frage() =>
        buendel.hole('fixture|1', const Duration(minutes: 5), () async {
          abrufe++;
          if (abrufe == 1) throw StateError('Netz weg');
          return abrufe;
        });

    await expectLater(frage(), throwsStateError);
    expect(await frage(), 2, reason: 'der zweite Versuch fragt wirklich');
    expect(buendel.gemerkt, 1);
  });

  test('der Fehler erreicht alle Wartenden', () async {
    final buendel = AbfrageBuendel();
    Future<int> frage() =>
        buendel.hole('x', const Duration(minutes: 5), () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw StateError('kaputt');
        });
    // **Beide Erwartungen vor dem Warten anhängen.** Wer die zweite erst
    // nach der ersten anhängt, hängt sie an einen Future, der längst
    // gescheitert ist — der Fehler gilt dann als unbehandelt, und der Test
    // fällt an einer Stelle, an der nichts kaputt ist.
    final a = expectLater(frage(), throwsStateError);
    final b = expectLater(frage(), throwsStateError);
    await a;
    await b;
  });

  test('leeren macht den Weg für „zum Neuladen ziehen" frei', () async {
    // Eine ausdrückliche Geste muss wirklich neu laden — sonst käme dieselbe
    // Zahl aus dem Speicher, und die Geste liefe ins Leere.
    var abrufe = 0;
    final buendel = AbfrageBuendel();
    Future<int> frage(String k) =>
        buendel.hole(k, const Duration(minutes: 5), () async => ++abrufe);

    await frage('seasonFixtures|82');
    await frage('standings|82');
    expect(abrufe, 2);

    buendel.leeren('standings');
    await frage('seasonFixtures|82');
    expect(abrufe, 2, reason: 'der Spielplan war nicht gemeint');
    await frage('standings|82');
    expect(abrufe, 3);

    buendel.leeren();
    await frage('seasonFixtures|82');
    expect(abrufe, 4);
  });

  test('eine laufende Frage überlebt das Leeren', () async {
    // Sie abzubrechen hieße, den Wartenden eine Antwort wegzunehmen, die
    // gleich da ist.
    final steuerung = Completer<int>();
    final buendel = AbfrageBuendel();
    final antwort =
        buendel.hole('y', const Duration(minutes: 5), () => steuerung.future);
    buendel.leeren();
    steuerung.complete(7);
    expect(await antwort, 7);
  });
}
