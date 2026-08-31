import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/providers.dart';

/// **Der Spieltag, den man aufstellt, ist nicht der, den man anschaut.**
///
/// Gemeldete Lücke: Zwischen der Waiver-Frist (Montag 15:00) und dem
/// Spieltagswechsel (24 h nach dem letzten Anpfiff, also Montag 17:30) konnte
/// man Spieler holen, sie aber nirgends hinstellen — der Aufstellungs-Schirm
/// zeigte noch den alten, komplett gesperrten Spieltag.
Fixture _f(int runde, DateTime anpfiff, FixtureStatus stand) => Fixture(
      id: 'sportmonks:$runde-${anpfiff.millisecondsSinceEpoch}',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: 'Spieltag $runde',
      kickoff: anpfiff,
      home: TeamRef(id: 'h$runde', name: 'Heim $runde', shortName: 'H'),
      away: TeamRef(id: 'a$runde', name: 'Aus $runde', shortName: 'A'),
      status: stand,
    );

List<Fixture> _saison({required FixtureStatus runde1}) => [
      _f(1, DateTime(2026, 8, 28, 20, 30), runde1),
      _f(1, DateTime(2026, 8, 30, 17, 30), runde1),
      _f(2, DateTime(2026, 9, 4, 20, 30), FixtureStatus.scheduled),
      _f(2, DateTime(2026, 9, 6, 17, 30), FixtureStatus.scheduled),
    ];

void main() {
  test('vor dem Spieltag stellt man diesen Spieltag auf', () {
    final s = _saison(runde1: FixtureStatus.scheduled);
    expect(aufstellungsRunde(s, DateTime(2026, 8, 27)), 1);
  });

  test('während der Spieltag läuft, bleibt es bei ihm', () {
    // Zwei Spiele, das Sonntagsspiel steht noch aus.
    final s = [
      _f(1, DateTime(2026, 8, 28, 20, 30), FixtureStatus.finished),
      _f(1, DateTime(2026, 8, 30, 17, 30), FixtureStatus.scheduled),
      _f(2, DateTime(2026, 9, 4, 20, 30), FixtureStatus.scheduled),
    ];
    expect(aufstellungsRunde(s, DateTime(2026, 8, 29, 12)), 1);
  });

  test('ist der Spieltag abgepfiffen, stellt man sofort den nächsten auf', () {
    // **Der Kern.** Sonntag 20:00: Runde 1 durch, der Spieltagswechsel der
    // Anzeige käme erst Montag 17:30.
    final s = _saison(runde1: FixtureStatus.finished);
    expect(aufstellungsRunde(s, DateTime(2026, 8, 30, 20)), 2);
    expect(currentFantasyRound(s, DateTime(2026, 8, 30, 20)), 1,
        reason: 'Die Anzeige bleibt bewusst einen Tag stehen');
  });

  test('die Lücke von Montag 15:00 bis 17:30 gibt es nicht mehr', () {
    final s = _saison(runde1: FixtureStatus.finished);
    expect(aufstellungsRunde(s, DateTime(2026, 8, 31, 15, 1)), 2);
    expect(aufstellungsRunde(s, DateTime(2026, 8, 31, 17, 31)), 2,
        reason: 'Und danach natürlich auch');
  });

  test('am Saisonende wird keine Runde erfunden', () {
    final s = [
      _f(34, DateTime(2027, 5, 15, 15, 30), FixtureStatus.finished),
    ];
    expect(aufstellungsRunde(s, DateTime(2027, 5, 15, 20)), 34);
  });

  test('ohne Spielplan bleibt es bei der Regel der Anzeige', () {
    expect(aufstellungsRunde(const [], DateTime(2026, 8, 30)), 1);
  });

  group('recapRunde', () {
    test('vor dem ersten Spieltag gibt es nichts zurückzublicken', () {
      final s = _saison(runde1: FixtureStatus.scheduled);
      expect(recapRunde(s, DateTime(2026, 8, 27)), isNull);
    });

    test('nach dem Abpfiff zeigt er den gelaufenen Spieltag', () {
      final s = _saison(runde1: FixtureStatus.finished);
      expect(recapRunde(s, DateTime(2026, 8, 30, 20)), 1);
    });

    test('und bleibt über die Waiver-Frist hinaus stehen', () {
      // **Der Kern der Regel.** Der aktuelle Spieltag springt montags um
      // 15:00 auf 2; ein Rückblick auf einen ungespielten Spieltag wäre leer.
      final s = _saison(runde1: FixtureStatus.finished);
      expect(currentFantasyRound(s, DateTime(2026, 8, 31, 15)), 2);
      expect(recapRunde(s, DateTime(2026, 8, 31, 15)), 1);
      expect(recapRunde(s, DateTime(2026, 9, 4, 20, 29)), 1,
          reason: 'Bis kurz vor dem Anstoß des nächsten');
    });

    test('mit dem Anstoß des nächsten Spieltags ist er vorbei', () {
      final s = _saison(runde1: FixtureStatus.finished);
      expect(recapRunde(s, DateTime(2026, 9, 4, 20, 30)), isNull);
    });

    test('ein laufender Spieltag ist kein Rückblick', () {
      final s = [
        _f(1, DateTime(2026, 8, 28, 20, 30), FixtureStatus.finished),
        _f(1, DateTime(2026, 8, 30, 17, 30), FixtureStatus.live),
      ];
      expect(recapRunde(s, DateTime(2026, 8, 30, 18)), isNull);
    });
  });
}
