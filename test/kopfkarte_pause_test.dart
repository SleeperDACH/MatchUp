import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_favorit_wahl.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/features/favorites/favorites.dart';
import 'package:matchup/features/favorites/logic/next_favorite_fixtures.dart';

/// Kopfkarte in der Pause und Nationalmannschaft als Favorit (10.11.2026).
TeamFixture _spiel(String id, DateTime k,
        {FixtureStatus status = FixtureStatus.scheduled}) =>
    TeamFixture(
      id: id,
      kickoff: k,
      status: status,
      leagueName: 'Bundesliga',
      home: const TeamRef(id: 'sportmonks:1', name: 'A', shortName: 'A'),
      away: const TeamRef(id: 'sportmonks:2', name: 'B', shortName: 'B'),
    );

void main() {
  // Dienstag in der Länderspielpause.
  final jetzt = DateTime(2026, 11, 10, 12);

  test('Pause: das nächste Spiel, auch zehn Tage weg', () {
    final spiele = kopfkartenSpiele(fixtures: [
      _spiel('alt', DateTime(2026, 11, 8, 15, 30),
          status: FixtureStatus.finished),
      _spiel('spaeter', DateTime(2026, 11, 21, 15, 30)),
      _spiel('naechstes', DateTime(2026, 11, 20, 20, 30)),
    ], jetzt: jetzt);
    expect(spiele.map((f) => f.id), ['naechstes']);
  });

  test('Pause: gleiche Anstoßzeit → alle, der Rang entscheidet danach', () {
    final spiele = kopfkartenSpiele(fixtures: [
      _spiel('x', DateTime(2026, 11, 21, 15, 30)),
      _spiel('y', DateTime(2026, 11, 21, 15, 30)),
      _spiel('z', DateTime(2026, 11, 22, 17, 30)),
    ], jetzt: jetzt);
    expect(spiele.map((f) => f.id), unorderedEquals(['x', 'y']));
  });

  test('Spiel im Fenster: die Regel des Wochenendes gilt unverändert', () {
    final spiele = kopfkartenSpiele(fixtures: [
      _spiel('freitag', DateTime(2026, 11, 13, 20, 45)), // Länderspiel
      _spiel('spaeter', DateTime(2026, 11, 20, 20, 30)),
    ], jetzt: jetzt);
    expect(spiele.map((f) => f.id), ['freitag']);
  });

  test('Nichts mehr geplant → nichts', () {
    expect(kopfkartenSpiele(fixtures: const [], jetzt: jetzt), isEmpty);
  });

  test('Nationalmannschaft ersetzt keinen Verein in der Vereinswahl', () {
    final deutschland = Favorite.nation(Leagues.deutschland);
    expect(isNationFavorite(deutschland), isTrue);
    expect(isResolvableTeamFavorite(deutschland), isFalse,
        reason: 'darf nie als Sportmonks-Vereins-ID gelesen werden');
    expect(
      zeigeFavoritWahl(
          angemeldet: true, geladen: true, favoriten: [deutschland]),
      isTrue,
    );
  });
}
