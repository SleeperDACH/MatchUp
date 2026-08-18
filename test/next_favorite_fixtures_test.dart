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
  final jetzt = DateTime(2026, 8, 18, 12, 0);

  test('nimmt das nächste Spiel und alles Weitere an dem Tag', () {
    final list = naechsteFavoritenSpiele(
      fixtures: [
        _fx('a', 'fcb', 'x', DateTime(2026, 8, 22, 15, 30)),
        _fx('b', 'y', 'bvb', DateTime(2026, 8, 22, 18, 30)),
        _fx('c', 'fcb', 'z', DateTime(2026, 8, 23, 15, 30)), // anderer Tag
      ],
      jetzt: jetzt,
    );
    expect(list.map((f) => f.id), ['a', 'b']);
  });

  test('Pokalspiel vor dem Ligaspiel zählt als das nächste', () {
    final list = naechsteFavoritenSpiele(
      fixtures: [
        _fx('liga', 'bvb', 'hsv', DateTime(2026, 8, 29, 18, 30)),
        _fx('pokal', 'verl', 'hsv', DateTime(2026, 8, 24, 18, 0),
            liga: 'DFB-Pokal'),
      ],
      jetzt: jetzt,
    );
    expect(list.map((f) => f.id), ['pokal']);
  });

  test('Favorit gegen Favorit steht nur einmal drin', () {
    final doppelt = _fx('a', 'fcb', 'bvb', DateTime(2026, 8, 22, 15, 30));
    final list = naechsteFavoritenSpiele(
        fixtures: [doppelt, doppelt], jetzt: jetzt);
    expect(list, hasLength(1));
  });

  test('Beendetes zählt nicht mit, Laufendes schon', () {
    final list = naechsteFavoritenSpiele(
      fixtures: [
        _fx('alt', 'fcb', 'x', DateTime(2026, 8, 15, 15, 30),
            status: FixtureStatus.finished),
        _fx('live', 'fcb', 'y', DateTime(2026, 8, 18, 11, 30),
            status: FixtureStatus.live),
      ],
      jetzt: jetzt,
    );
    expect(list.map((f) => f.id), ['live']);
  });

  test('ohne Spiele: leer', () {
    expect(naechsteFavoritenSpiele(fixtures: const [], jetzt: jetzt), isEmpty);
  });

  test('Spiele sind nach Anstoß sortiert', () {
    final list = naechsteFavoritenSpiele(
      fixtures: [
        _fx('spaet', 'fcb', 'x', DateTime(2026, 8, 22, 18, 30)),
        _fx('frueh', 'bvb', 'y', DateTime(2026, 8, 22, 15, 30)),
      ],
      jetzt: jetzt,
    );
    expect(list.map((f) => f.id), ['frueh', 'spaet']);
  });
}
