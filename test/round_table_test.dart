import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/data/odds/frozen_odds.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/tippspiel/logic/round_table.dart';
import 'package:meine_app/features/tippspiel/models/tip.dart';
import 'package:meine_app/features/tippspiel/models/tip_round.dart';

Fixture _fixture(String id, {int? home, int? away}) => Fixture(
      id: id,
      leagueId: 'wm2026',
      season: 2026,
      round: 1,
      roundName: 'Gruppenphase 1',
      kickoff: DateTime.utc(2026, 6, 11, 19),
      home: const TeamRef(id: 't1', name: 'Mexiko', shortName: 'MEX'),
      away: const TeamRef(id: 't2', name: 'Südafrika', shortName: 'RSA'),
      status:
          home == null ? FixtureStatus.scheduled : FixtureStatus.finished,
      homeScore: home,
      awayScore: away,
    );

void main() {
  test('totalPointsByMember: Kicktipp-Wertung, Mitglieder ohne Tipps = 0', () {
    const anna = RoundMember(userId: 'a', username: 'anna');
    const ben = RoundMember(userId: 'b', username: 'ben');
    const neu = RoundMember(userId: 'n', username: 'neu');

    final fixtures = [
      _fixture('f1', home: 2, away: 1), // beendet 2:1
      _fixture('f2', home: 0, away: 0), // beendet 0:0
      _fixture('f3'), // noch nicht gespielt
    ];
    final tips = [
      // anna: exakt (4) + Tendenz-Unentschieden über Differenz (3) = 7
      const MemberTip(userId: 'a', fixtureId: 'f1', homeGoals: 2, awayGoals: 1),
      const MemberTip(userId: 'a', fixtureId: 'f2', homeGoals: 1, awayGoals: 1),
      // ben: Tendenz (2) + falsch (0) = 2; Tipp auf offenes Spiel zählt nicht
      const MemberTip(userId: 'b', fixtureId: 'f1', homeGoals: 3, awayGoals: 0),
      const MemberTip(userId: 'b', fixtureId: 'f2', homeGoals: 1, awayGoals: 0),
      const MemberTip(userId: 'b', fixtureId: 'f3', homeGoals: 5, awayGoals: 5),
    ];

    final totals = totalPointsByMember(
      members: const [anna, ben, neu],
      tips: tips,
      fixtures: fixtures,
      rules: ScoringRules.kicktippDefault,
    );

    expect(totals['a'], 7);
    expect(totals['b'], 2);
    expect(totals['n'], 0, reason: 'Neue Mitglieder erscheinen mit 0 Punkten');
  });

  test('ranksByPoints: Plätze mit Gleichstand (1, 2, 2, 4)', () {
    const a = RoundMember(userId: 'a', username: 'anna');
    const b = RoundMember(userId: 'b', username: 'ben');
    const c = RoundMember(userId: 'c', username: 'cara');
    const d = RoundMember(userId: 'd', username: 'dan');
    final ranks = ranksByPoints(
      const [a, b, c, d],
      {'a': 10, 'b': 7, 'c': 7, 'd': 3},
    );
    expect(ranks['a'], 1);
    expect(ranks['b'], 2);
    expect(ranks['c'], 2, reason: 'Gleiche Punkte -> gleicher Platz');
    expect(ranks['d'], 4, reason: 'Nach Gleichstand wird der Platz übersprungen');
  });

  test('ranksByPoints: Bewegung ggü. vorherigem Stand', () {
    const a = RoundMember(userId: 'a', username: 'anna');
    const b = RoundMember(userId: 'b', username: 'ben');
    final before = ranksByPoints(const [a, b], {'a': 3, 'b': 5}); // b vorn
    final after = ranksByPoints(const [a, b], {'a': 9, 'b': 5}); // a überholt
    expect(before['a']! - after['a']!, 1, reason: 'anna klettert von 2 auf 1');
    expect(before['b']! - after['b']!, -1, reason: 'ben fällt von 1 auf 2');
  });

  test('totalPointsByMember: laufende Spiele zählen mit Live-Stand mit', () {
    final live = Fixture(
      id: 'fLive',
      leagueId: 'wm2026',
      season: 2026,
      round: 1,
      roundName: 'Gruppenphase 1',
      kickoff: DateTime.utc(2026, 6, 11, 19),
      home: const TeamRef(id: 't1', name: 'Mexiko', shortName: 'MEX'),
      away: const TeamRef(id: 't2', name: 'Südafrika', shortName: 'RSA'),
      status: FixtureStatus.live,
      homeScore: 1,
      awayScore: 0,
    );
    final tips = [
      // exakter Live-Tipp 1:0 -> volle Punkte (4)
      const MemberTip(
          userId: 'a', fixtureId: 'fLive', homeGoals: 1, awayGoals: 0),
    ];

    final totals = totalPointsByMember(
      members: const [RoundMember(userId: 'a', username: 'anna')],
      tips: tips,
      fixtures: [live],
      rules: ScoringRules.kicktippDefault,
    );

    expect(totals['a'], ScoringRules.kicktippDefault.exact);
  });

  test('Alleinstellungs-Bonus: nur der einzige exakte Treffer bekommt ihn', () {
    const anna = RoundMember(userId: 'a', username: 'anna');
    const ben = RoundMember(userId: 'b', username: 'ben');
    const cara = RoundMember(userId: 'c', username: 'cara');

    final fixtures = [
      _fixture('f1', home: 2, away: 1), // anna allein exakt
      _fixture('f2', home: 0, away: 0), // anna + ben beide exakt -> kein Solo
    ];
    final tips = [
      const MemberTip(userId: 'a', fixtureId: 'f1', homeGoals: 2, awayGoals: 1),
      const MemberTip(userId: 'b', fixtureId: 'f1', homeGoals: 1, awayGoals: 0),
      const MemberTip(userId: 'a', fixtureId: 'f2', homeGoals: 0, awayGoals: 0),
      const MemberTip(userId: 'b', fixtureId: 'f2', homeGoals: 0, awayGoals: 0),
      const MemberTip(userId: 'c', fixtureId: 'f2', homeGoals: 1, awayGoals: 0),
    ];

    const rules = ScoringRules(solo: 3); // Basiswertung Standard + Solo 3
    final totals = totalPointsByMember(
      members: const [anna, ben, cara],
      tips: tips,
      fixtures: fixtures,
      rules: rules,
    );

    // anna: f1 exakt(4)+Solo(3)=7, f2 exakt(4) aber geteilt -> +0 = 11
    expect(totals['a'], 11);
    // ben: f1 Tordifferenz(3) (1:0 auf 2:1), f2 exakt(4) geteilt -> 7
    expect(totals['b'], 7);
    expect(totals['c'], 0);
  });

  test('oddsBonus-Flag: aus -> kein Quoten-Bonus, an -> Bonus zählt', () {
    const anna = RoundMember(userId: 'a', username: 'anna');
    final fixtures = [_fixture('f1', home: 1, away: 0)]; // Heimsieg
    final tips = [
      const MemberTip(userId: 'a', fixtureId: 'f1', homeGoals: 1, awayGoals: 0),
    ];
    // Krasser Außenseiter-Heimsieg (Quote > 5.0) -> +5 Bonus.
    const odds = {
      'f1': FrozenOdds(fixtureId: 'f1', homeWin: 6.0, draw: 4.0, awayWin: 1.4),
    };

    final off = totalPointsByMember(
      members: const [anna],
      tips: tips,
      fixtures: fixtures,
      rules: const ScoringRules(oddsBonus: false),
      frozenOdds: odds,
    );
    final on = totalPointsByMember(
      members: const [anna],
      tips: tips,
      fixtures: fixtures,
      rules: const ScoringRules(oddsBonus: true),
      frozenOdds: odds,
    );

    expect(off['a'], 4, reason: 'nur Basispunkte (exakt)');
    expect(on['a'], 9, reason: 'exakt(4) + Quoten-Bonus(5)');
  });
}
