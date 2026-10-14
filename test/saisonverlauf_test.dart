import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/logic/round_robin.dart';
import 'package:matchup/features/fantasy/logic/saisonverlauf.dart';

void main() {
  const ids = ['a', 'b', 'c', 'd'];

  test('jeder Spieltag hat genau den Gegner aus den Paarungen', () {
    final verlauf = saisonverlauf(
      ids: ids,
      managerId: 'a',
      gewertet: const {},
      letzteRunde: 6,
    );
    expect(verlauf.map((s) => s.runde), [1, 2, 3, 4, 5, 6]);
    for (final s in verlauf) {
      final paar = roundPairings(ids, s.runde)
          .firstWhere((m) => m.home == 'a' || m.away == 'a');
      expect(s.gegnerId, paar.home == 'a' ? paar.away : paar.home);
    }
    // Bei vier Teilnehmern spielt jeder in drei Runden gegen jeden.
    expect(verlauf.take(3).map((s) => s.gegnerId).toSet(), {'b', 'c', 'd'});
  });

  test('gewertete Spieltage tragen Punkte und Ausgang, ungewertete nicht', () {
    final gegner1 = saisonverlauf(
      ids: ids,
      managerId: 'a',
      gewertet: const {},
      letzteRunde: 1,
    ).single.gegnerId!;
    final verlauf = saisonverlauf(
      ids: ids,
      managerId: 'a',
      gewertet: {
        1: {'a': 120.4, gegner1: 99.5},
      },
      letzteRunde: 2,
    );
    expect(verlauf[0].gewertet, isTrue);
    expect(verlauf[0].eigene, 120.4);
    expect(verlauf[0].gegner, 99.5);
    expect(verlauf[0].ausgang, DuellAusgang.sieg);
    expect(verlauf[1].gewertet, isFalse);
    expect(verlauf[1].ausgang, isNull);
  });

  test('der Ausgang deckt sich mit der Tabelle', () {
    // Dieselbe Grundlage muss in Profil und Tabelle dieselbe Bilanz ergeben.
    final gewertet = <int, Map<String, num>>{
      1: {'a': 100, 'b': 90, 'c': 80, 'd': 80},
      2: {'a': 70, 'b': 90, 'c': 60, 'd': 50},
      3: {'a': 75, 'b': 75, 'c': 75, 'd': 75},
    };
    for (final id in ids) {
      final verlauf = saisonverlauf(
          ids: ids, managerId: id, gewertet: gewertet, letzteRunde: 3);
      final rec = h2hStandings(ids, gewertet)
          .firstWhere((r) => r.managerId == id);
      int zaehle(DuellAusgang a) =>
          verlauf.where((s) => s.ausgang == a).length;
      expect(zaehle(DuellAusgang.sieg), rec.wins, reason: id);
      expect(zaehle(DuellAusgang.unentschieden), rec.ties, reason: id);
      expect(zaehle(DuellAusgang.niederlage), rec.losses, reason: id);
    }
  });

  test('bei ungerader Zahl ist man auch mal spielfrei — und das zählt nicht',
      () {
    const drei = ['a', 'b', 'c'];
    final gewertet = <int, Map<String, num>>{
      for (var r = 1; r <= 3; r++) r: {'a': 50, 'b': 40, 'c': 30},
    };
    final verlauf = saisonverlauf(
        ids: drei, managerId: 'a', gewertet: gewertet, letzteRunde: 3);
    final frei = verlauf.where((s) => s.spielfrei).toList();
    expect(frei, hasLength(1));
    expect(frei.single.gewertet, isFalse,
        reason: 'Spielfrei hat keinen Gegner und keine Punkte im Duell');
  });

  test('unbekannter Manager ergibt keinen Verlauf', () {
    expect(
      saisonverlauf(
          ids: ids, managerId: 'x', gewertet: const {}, letzteRunde: 34),
      isEmpty,
    );
  });
}
