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
    // Rangkarte: fcb ist der oberste Favorit, bvb der zweite.
    int? rang(TeamFixture f) => switch ((f.home.id, f.away.id)) {
      (_, _) when f.home.id == 'fcb' || f.away.id == 'fcb' => 0,
      (_, _) when f.home.id == 'bvb' || f.away.id == 'bvb' => 1,
      _ => null,
    };

    test('das Spiel des obersten Favoriten kommt nach vorn', () {
      // Der BVB stößt früher an — auf die Kopfkarte gehört trotzdem Bayern.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('frueh', 'bvb', 'x', DateTime(2026, 8, 22, 13, 30)),
          _fx('spaet', 'fcb', 'y', DateTime(2026, 8, 22, 18, 30)),
        ],
        rang: rang,
      );
      expect(list.map((f) => f.id), ['spaet', 'frueh']);
    });

    test('der Rest bleibt nach Anstoß sortiert', () {
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('a', 'bvb', 'x', DateTime(2026, 8, 22, 13, 30)),
          _fx('b', 'z', 'q', DateTime(2026, 8, 22, 15, 30)),
          _fx('c', 'fcb', 'y', DateTime(2026, 8, 22, 18, 30)),
        ],
        rang: rang,
      );
      expect(list.map((f) => f.id), ['c', 'a', 'b']);
    });

    test('steht der oberste Favorit schon vorn, ändert sich nichts', () {
      final spiele = [
        _fx('a', 'fcb', 'x', DateTime(2026, 8, 22, 13, 30)),
        _fx('b', 'bvb', 'y', DateTime(2026, 8, 22, 15, 30)),
      ];
      expect(identical(favoritenSpielZuerst(spiele: spiele, rang: rang), spiele),
          isTrue);
    });

    test('Favorit gegen Favorit zählt mit dem höheren Rang', () {
      // Das Duell trägt Rang 0 (Bayern) und schlägt das reine BVB-Spiel.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('bvb-solo', 'bvb', 'x', DateTime(2026, 8, 22, 13, 30)),
          _fx('duell', 'bvb', 'fcb', DateTime(2026, 8, 22, 18, 30)),
        ],
        rang: rang,
      );
      expect(list.first.id, 'duell');
    });

    test('kennt der Rang keinen der Vereine, bleibt die Reihenfolge', () {
      // Ein Spiel, das nur über den Gegner in die Liste geriet.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('a', 'fremd', 'auch-fremd', DateTime(2026, 8, 22, 13, 30)),
          _fx('b', 'noch-fremd', 'x', DateTime(2026, 8, 22, 15, 30)),
        ],
        rang: (_) => null,
      );
      expect(list.map((f) => f.id), ['a', 'b']);
    });

    test('ein abgepfiffenes Spiel kommt nicht auf die Kopfkarte', () {
      // **Die Kopfkarte zeigt das nächste Spiel.** Seit das Fenster die ganze
      // Fußballwoche umfasst, stehen auch gespielte Partien in der Liste —
      // ohne diese Regel landete am Sonntagabend das Freitagsspiel des
      // obersten Favoriten oben, während ein anderer Verein gerade noch
      // spielte.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('freitag', 'bs', 'x', DateTime(2026, 9, 11, 18, 30),
              status: FixtureStatus.finished),
          _fx('sonntag', 'hsv', 'y', DateTime(2026, 9, 13, 15, 30)),
        ],
        // Braunschweig steht oben in den Favoriten, hat aber schon gespielt.
        rang: (f) => f.home.name == 'bs' ? 0 : 1,
      );
      expect(list.first.id, 'sonntag');
    });

    test('unter den offenen gewinnt weiter der oberste Favorit', () {
      // Die alte Regel bleibt: Wer Bayern über Bochum stellt, will an einem
      // Samstag mit beiden Bayern oben sehen — nicht den früheren Anstoß.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('frueh', 'bochum', 'x', DateTime(2026, 9, 12, 13, 30)),
          _fx('spaet', 'bayern', 'y', DateTime(2026, 9, 12, 18, 30)),
        ],
        rang: (f) => f.home.name == 'bayern' ? 0 : 1,
      );
      expect(list.first.id, 'spaet');
    });

    test('ist alles gespielt, bleibt das Wochenende oben stehen', () {
      // Sonntagabend bis Montag 15:00: Es gibt kein nächstes Spiel mehr im
      // Fenster. Eine leere Kopfkarte wäre schlechter als das Ergebnis.
      final list = favoritenSpielZuerst(
        spiele: [
          _fx('a', 'bochum', 'x', DateTime(2026, 9, 12, 13, 30),
              status: FixtureStatus.finished),
          _fx('b', 'bayern', 'y', DateTime(2026, 9, 13, 18, 30),
              status: FixtureStatus.finished),
        ],
        rang: (f) => f.home.name == 'bayern' ? 0 : 1,
      );
      expect(list.first.id, 'b');
    });
  });

}
