import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/tippspiel/logic/team_form.dart';

Fixture _spiel(int tag, String heim, String gast, int? h, int? g,
        {FixtureStatus status = FixtureStatus.finished}) =>
    Fixture(
      id: 'sportmonks:$tag$heim$gast',
      leagueId: 'bundesliga',
      season: 2026,
      round: tag,
      roundName: '$tag. Spieltag',
      kickoff: DateTime.utc(2026, 9, tag),
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: gast, name: gast, shortName: gast),
      status: status,
      homeScore: h,
      awayScore: g,
    );

void main() {
  final saison = [
    _spiel(1, 'A', 'B', 2, 0), // A S
    _spiel(2, 'C', 'A', 1, 1), // A U
    _spiel(3, 'A', 'D', 0, 3), // A N
    _spiel(4, 'E', 'A', 0, 1), // A S (auswärts)
    _spiel(5, 'A', 'F', 2, 2), // A U
    _spiel(6, 'G', 'A', 4, 1), // A N
    _spiel(7, 'A', 'H', null, null, status: FixtureStatus.scheduled),
  ];

  test('die letzten fünf vor dem Spiel, älteste zuerst, aus eigener Sicht', () {
    final form = formVor(saison, 'A', DateTime.utc(2026, 9, 7));
    expect(form.map((e) => e.buchstabe).join(), 'UNSUN');
  });

  test('Spiele nach dem getippten zählen nicht mit', () {
    final form = formVor(saison, 'A', DateTime.utc(2026, 9, 4));
    expect(form.map((e) => e.buchstabe).join(), 'SUN');
  });

  test('laufende und offene Spiele sind kein Ergebnis', () {
    final mitLive = [
      ...saison,
      _spiel(6, 'A', 'X', 1, 0, status: FixtureStatus.live),
    ];
    final form = formVor(mitLive, 'A', DateTime.utc(2026, 9, 8));
    expect(form.length, 5);
    expect(form.last, FormErgebnis.niederlage);
  });

  test('ohne Spiele ist die Form leer', () {
    expect(formVor(saison, 'Z', DateTime.utc(2026, 9, 30)), isEmpty);
  });

  test('im Pokal zählt die Liga-Form', () {
    expect(formQuellen('dfb_pokal'), ['bundesliga', 'bundesliga2', 'liga3']);
    expect(formQuellen('bundesliga2'), ['bundesliga2']);
  });
}
