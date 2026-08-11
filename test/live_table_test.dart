import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/tippspiel/logic/live_table.dart';

TeamRef _t(String id) =>
    TeamRef(id: id, name: id.toUpperCase(), shortName: id.toUpperCase());

StandingRow _row(
  String id, {
  int rank = 1,
  int points = 0,
  int played = 0,
  int won = 0,
  int draw = 0,
  int lost = 0,
  int gf = 0,
  int ga = 0,
}) =>
    StandingRow(
      rank: rank,
      team: _t(id),
      points: points,
      played: played,
      won: won,
      draw: draw,
      lost: lost,
      goalsFor: gf,
      goalsAgainst: ga,
    );

Fixture _fx(
  String id,
  String home,
  String away, {
  int? hs,
  int? as_,
  FixtureStatus status = FixtureStatus.finished,
  int tageVorher = 0,
}) =>
    Fixture(
      id: id,
      leagueId: 'bundesliga',
      season: 2026,
      round: 1,
      roundName: '1. Spieltag',
      kickoff: DateTime.utc(2026, 8, 10).subtract(Duration(days: tageVorher)),
      home: _t(home),
      away: _t(away),
      homeScore: hs,
      awayScore: as_,
      status: status,
    );

void main() {
  group('mergeLiveResults', () {
    test('leere Tabelle bleibt leer', () {
      expect(mergeLiveResults(const [], [_fx('f1', 'a', 'b', hs: 1, as_: 0)]),
          isEmpty);
    });

    test('was die API schon kennt, wird nicht doppelt gezählt', () {
      // Beide Mannschaften haben laut API ihr Spiel bereits verbucht.
      final base = [
        _row('a', points: 3, played: 1, won: 1, gf: 2, ga: 1),
        _row('b', rank: 2, points: 0, played: 1, lost: 1, gf: 1, ga: 2),
      ];
      final out = mergeLiveResults(
          base, [_fx('f1', 'a', 'b', hs: 2, as_: 1)]);
      expect(out.first.points, 3);
      expect(out.first.played, 1);
      expect(out.last.points, 0);
    });

    test('ein beendetes Spiel, das die API noch nicht kennt, wird nachgetragen',
        () {
      final base = [_row('a'), _row('b', rank: 2)];
      final out =
          mergeLiveResults(base, [_fx('f1', 'a', 'b', hs: 2, as_: 1)]);
      final a = out.firstWhere((r) => r.team.id == 'a');
      final b = out.firstWhere((r) => r.team.id == 'b');
      expect(a.points, 3);
      expect(a.won, 1);
      expect(a.goalsFor, 2);
      expect(a.goalsAgainst, 1);
      expect(a.rank, 1);
      expect(b.points, 0);
      expect(b.lost, 1);
      expect(b.rank, 2);
    });

    test('Unentschieden bringt beiden einen Punkt', () {
      final out = mergeLiveResults([_row('a'), _row('b', rank: 2)],
          [_fx('f1', 'a', 'b', hs: 1, as_: 1)]);
      expect(out.every((r) => r.points == 1 && r.draw == 1), isTrue);
    });

    test('laufendes Spiel zählt mit Zwischenstand, lässt sich aber abschalten',
        () {
      final fixtures = [
        _fx('f1', 'a', 'b', hs: 1, as_: 0, status: FixtureStatus.live)
      ];
      final mit = mergeLiveResults([_row('a'), _row('b', rank: 2)], fixtures);
      expect(mit.firstWhere((r) => r.team.id == 'a').points, 3);

      final ohne = mergeLiveResults([_row('a'), _row('b', rank: 2)], fixtures,
          includeLive: false);
      expect(ohne.every((r) => r.points == 0), isTrue);
    });

    test('Punktabzüge der API bleiben erhalten', () {
      // −6 Punkte: Die API-Zeile weist trotz zweier Siege nur 0 Punkte aus.
      final base = [
        _row('a', points: 0, played: 2, won: 2, gf: 4, ga: 0),
        _row('b', rank: 2, points: 3, played: 1, won: 1, gf: 1, ga: 0),
      ];
      final out = mergeLiveResults(base, [
        _fx('f1', 'a', 'c', hs: 2, as_: 0, tageVorher: 5),
        _fx('f2', 'a', 'd', hs: 2, as_: 0, tageVorher: 3),
      ]);
      // Nichts nachzutragen (played stimmt), der Abzug bleibt stehen.
      expect(out.firstWhere((r) => r.team.id == 'a').points, 0);
      expect(out.first.team.id, 'b');
    });

    test('Sortierung: Punkte, dann Tordifferenz, dann erzielte Tore', () {
      final base = [
        _row('a', points: 3, played: 1, won: 1, gf: 1, ga: 0),
        _row('b', rank: 2, points: 3, played: 1, won: 1, gf: 5, ga: 0),
        _row('c', rank: 3, points: 3, played: 1, won: 1, gf: 3, ga: 1),
      ];
      final out = mergeLiveResults(base, const []);
      expect([for (final r in out) r.team.id], ['b', 'c', 'a']);
      expect([for (final r in out) r.rank], [1, 2, 3]);
    });

    test('Gegner außerhalb der Tabelle (Pokal) fließen nicht ein', () {
      final out = mergeLiveResults(
          [_row('a')], [_fx('f1', 'a', 'fremd', hs: 3, as_: 0)]);
      expect(out.single.points, 0, reason: 'Pokalspiel gehört nicht in die Liga');
    });

    test('Spiel ohne Ergebnis wird ignoriert', () {
      final out = mergeLiveResults([_row('a'), _row('b', rank: 2)],
          [_fx('f1', 'a', 'b', status: FixtureStatus.scheduled)]);
      expect(out.every((r) => r.played == 0), isTrue);
    });
  });
}
