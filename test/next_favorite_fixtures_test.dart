import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/features/favorites/logic/next_favorite_fixtures.dart';

TeamFixture _fx(String id, String home, String away, DateTime ko,
        {FixtureStatus status = FixtureStatus.scheduled,
        String liga = 'Bundesliga'}) =>
    TeamFixture(
      id: id,
      kickoff: ko,
      status: status,
      leagueName: liga,
      round: 1,
      home: TeamRef(id: home, name: home, shortName: home),
      away: TeamRef(id: away, name: away, shortName: away),
    );

void main() {
  // **Die Fensterregel ist umgezogen.** „Das nächste Spiel und alles am selben
  // Tag" gilt nicht mehr; der Homescreen zeigt die Fußballwoche von Freitag
  // bis Montag 15:00. Sie wird in `test/mein_wochenende_test.dart` geprüft.
  // Hier bleibt, was unverändert gilt: welches der Spiele die Kopfkarte trägt.

  group('favoritenSpielZuerst', () {
    // **Der nächste Anpfiff gewinnt** (auf Ansage, 07.09.2026). Der
    // Favoritenrang entscheidet nur bei gleicher Anstoßzeit. Vorher galt der
    // Rang unbedingt — das schob eine Partie nach oben, die erst Stunden
    // später beginnt, während eine andere schon läuft.
    int? rangVon(TeamFixture f) => switch (f.home.name) {
          'bayern' => 0,
          'bochum' => 1,
          'hsv' => 2,
          _ => null,
        };

    test('der frühere Anstoß kommt nach vorn, auch beim kleineren Favoriten',
        () {
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('spaet', 'bayern', 'x', DateTime(2026, 9, 12, 18, 30)),
          _fx('frueh', 'bochum', 'y', DateTime(2026, 9, 12, 13, 30)),
        ],
        rang: rangVon,
      );
      expect(list.first.id, 'frueh');
    });

    test('bei gleicher Anstoßzeit entscheidet der Favoritenrang', () {
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('bochum', 'bochum', 'x', DateTime(2026, 9, 12, 15, 30)),
          _fx('bayern', 'bayern', 'y', DateTime(2026, 9, 12, 15, 30)),
          _fx('hsv', 'hsv', 'z', DateTime(2026, 9, 12, 15, 30)),
        ],
        rang: rangVon,
      );
      expect(list.first.id, 'bayern');
    });

    test('ein unbekannter Verein verliert den Gleichstand', () {
      // Ein Spiel, das nur über den Gegner in die Liste geraten ist, gehört
      // nicht auf die Kopfkarte.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('fremd', 'irgendwer', 'x', DateTime(2026, 9, 12, 15, 30)),
          _fx('hsv', 'hsv', 'y', DateTime(2026, 9, 12, 15, 30)),
        ],
        rang: rangVon,
      );
      expect(list.first.id, 'hsv');
    });

    test('ein abgepfiffenes Spiel kommt nicht auf die Kopfkarte', () {
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('freitag', 'bayern', 'x', DateTime(2026, 9, 11, 18, 30),
              status: FixtureStatus.finished),
          _fx('sonntag', 'hsv', 'y', DateTime(2026, 9, 13, 15, 30)),
        ],
        rang: rangVon,
      );
      expect(list.first.id, 'sonntag');
    });

    test('ist alles gespielt, steht das zuletzt gespielte oben', () {
      // Sonntagabend bis Montag 15:00: Es gibt keinen nächsten Anpfiff mehr im
      // Fenster. Dann ist das jüngste Ergebnis das, worüber man redet.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('freitag', 'bayern', 'x', DateTime(2026, 9, 11, 18, 30),
              status: FixtureStatus.finished),
          _fx('sonntag', 'bochum', 'y', DateTime(2026, 9, 13, 17, 30),
              status: FixtureStatus.finished),
        ],
        rang: rangVon,
      );
      expect(list.first.id, 'sonntag');
    });

    test('der Rest behält seine Reihenfolge', () {
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('a', 'bayern', 'x', DateTime(2026, 9, 12, 18, 30)),
          _fx('b', 'bochum', 'y', DateTime(2026, 9, 12, 13, 30)),
          _fx('c', 'hsv', 'z', DateTime(2026, 9, 13, 15, 30)),
        ],
        rang: rangVon,
      );
      expect(list.map((f) => f.id), ['b', 'a', 'c']);
    });

    test('kennt der Rang keinen der Vereine, zählt allein die Zeit', () {
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('spaet', 'fremd', 'x', DateTime(2026, 9, 12, 18, 30)),
          _fx('frueh', 'auch-fremd', 'y', DateTime(2026, 9, 12, 13, 30)),
        ],
        rang: (_) => null,
      );
      expect(list.first.id, 'frueh');
    });
  });
}
