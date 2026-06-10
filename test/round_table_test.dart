import 'package:flutter_test/flutter_test.dart';
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
}
