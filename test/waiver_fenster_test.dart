import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/waiver_fenster.dart';

/// **Die Waiver-Frist: Montag 15:00, in englischen Wochen Donnerstag 15:00.**
///
/// Gerechnet wird in Ortszeit, und zwar mit Absicht: „Montag 15 Uhr" ist eine
/// Uhrzeit für Menschen. Der Test läuft deshalb bewusst über die Zeitumstellung
/// hinweg — in UTC gerechnet läge die Novemberfrist eine Stunde daneben.
Fixture _f(String id, int runde, DateTime anpfiff, String heim, String aus) =>
    Fixture(
      id: id,
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: 'Spieltag $runde',
      kickoff: anpfiff,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: aus, name: aus, shortName: aus),
      status: FixtureStatus.scheduled,
    );

void main() {
  // Ein gewöhnlicher Spieltag: Freitag 20:30 bis Sonntag 17:30.
  final normal = [
    _f('n1', 1, DateTime(2026, 8, 28, 20, 30), 'Bayern', 'Leipzig'),
    _f('n2', 1, DateTime(2026, 8, 29, 15, 30), 'Leverkusen', 'Elversberg'),
    _f('n3', 1, DateTime(2026, 8, 30, 17, 30), 'Dortmund', 'HSV'),
  ];

  test('normaler Spieltag: Frist ist der Montag danach, 15:00', () {
    expect(waiverFrist(normal, 1), DateTime(2026, 8, 31, 15));
  });

  test('englische Woche (Di und Mi): Frist ist der Donnerstag', () {
    final englisch = [
      _f('e1', 5, DateTime(2026, 9, 22, 18, 30), 'Bayern', 'Leipzig'),
      _f('e2', 5, DateTime(2026, 9, 22, 20, 45), 'Leverkusen', 'Mainz'),
      _f('e3', 5, DateTime(2026, 9, 23, 20, 45), 'Dortmund', 'HSV'),
    ];
    expect(waiverFrist(englisch, 5), DateTime(2026, 9, 24, 15));
  });

  test('nur Dienstagsspiele sind keine englische Woche', () {
    // Die Regel verlangt Dienstag **und** Mittwoch. Ein einzelner
    // Dienstagstermin (Pokal-Nachholer) verschiebt die Frist nicht.
    final nurDi = [
      _f('d1', 6, DateTime(2026, 9, 22, 20, 30), 'Bayern', 'Leipzig'),
    ];
    expect(waiverFrist(nurDi, 6), DateTime(2026, 9, 28, 15),
        reason: 'Der nächste Montag, nicht der Donnerstag');
  });

  test('die Frist rutscht über die Zeitumstellung nicht weg', () {
    final november = [
      _f('w1', 12, DateTime(2026, 11, 29, 17, 30), 'Bayern', 'Leipzig'),
    ];
    final frist = waiverFrist(november, 12)!;
    expect(frist, DateTime(2026, 11, 30, 15));
    expect(frist.hour, 15, reason: 'Ortszeit, nicht UTC');
  });

  group('wireRunde', () {
    test('vor dem ersten Anpfiff ist der Waiver zu', () {
      expect(wireRunde(normal, DateTime(2026, 8, 28, 12)), isNull);
    });
    test('zwischen Anpfiff und Frist ist er offen', () {
      expect(wireRunde(normal, DateTime(2026, 8, 29, 18)), 1);
      expect(wireRunde(normal, DateTime(2026, 8, 31, 14, 59)), 1);
    });
    test('nach der Frist ist er wieder zu', () {
      expect(wireRunde(normal, DateTime(2026, 8, 31, 15, 1)), isNull);
    });
  });

  group('vereinAufWire', () {
    test('erst ab dem Anpfiff des eigenen Vereins', () {
      // **Der Kern der Regel.** Freitag um 21 Uhr läuft der Spieltag, aber
      // Dortmund spielt erst Sonntag — seine Spieler sind noch direkt zu holen.
      final freitagAbend = DateTime(2026, 8, 28, 21);
      expect(vereinAufWire('Bayern', normal, freitagAbend), isTrue);
      expect(vereinAufWire('Dortmund', normal, freitagAbend), isFalse);
    });

    test('nach der Frist ist auch der Freitagsverein wieder frei', () {
      expect(vereinAufWire('Bayern', normal, DateTime(2026, 8, 31, 15, 1)),
          isFalse);
    });

    test('ein Verein ohne Ansetzung liegt nie auf dem Waiver', () {
      // Der Pool enthält auch Spieler aus anderen Ligen.
      expect(vereinAufWire('AS Monaco', normal, DateTime(2026, 8, 29, 18)),
          isFalse);
    });
  });

  test('fristKurz schreibt die Frist so hin, wie sie in der Zeile steht', () {
    expect(fristKurz(DateTime(2026, 8, 31, 15)), 'Mo, 15:00');
    expect(fristKurz(DateTime(2026, 9, 24, 15)), 'Do, 15:00');
  });
}
