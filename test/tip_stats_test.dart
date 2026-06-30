import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/tippspiel/logic/tip_stats.dart';
import 'package:meine_app/features/tippspiel/models/tip.dart';
import 'package:meine_app/features/tippspiel/models/tip_round.dart';

Fixture _fx(String id, {int? home, int? away}) => Fixture(
      id: id,
      leagueId: 'wm2026',
      season: 2026,
      round: 1,
      roundName: 'Gruppenphase 1',
      kickoff: DateTime.utc(2026, 6, 11, 19),
      home: const TeamRef(id: 't1', name: 'A', shortName: 'A'),
      away: const TeamRef(id: 't2', name: 'B', shortName: 'B'),
      status: home == null ? FixtureStatus.scheduled : FixtureStatus.finished,
      homeScore: home,
      awayScore: away,
    );

TipRound _round() => TipRound(
      id: 'r1',
      name: 'Runde',
      leagueId: 'wm2026',
      season: 2026,
      inviteCode: 'abc',
      scoring: ScoringRules.kicktippDefault,
      createdBy: 'me',
    );

void main() {
  test('computeTipStats: Bilanz nur über beendete Spiele, fremde ignoriert',
      () {
    final fixtures = {
      'f1': _fx('f1', home: 2, away: 1), // exakt
      'f2': _fx('f2', home: 3, away: 1), // Tendenz (Heimsieg)
      'f3': _fx('f3', home: 2, away: 2), // Tordifferenz (Remis)
      'f4': _fx('f4', home: 1, away: 0), // daneben
      'f5': _fx('f5'), // nicht gespielt -> ignoriert
    };
    final tips = [
      const MemberTip(userId: 'me', fixtureId: 'f1', homeGoals: 2, awayGoals: 1),
      const MemberTip(userId: 'me', fixtureId: 'f2', homeGoals: 1, awayGoals: 0),
      const MemberTip(userId: 'me', fixtureId: 'f3', homeGoals: 1, awayGoals: 1),
      const MemberTip(userId: 'me', fixtureId: 'f4', homeGoals: 0, awayGoals: 2),
      const MemberTip(userId: 'me', fixtureId: 'f5', homeGoals: 5, awayGoals: 5),
      // anderer Nutzer -> darf nicht zählen
      const MemberTip(userId: 'x', fixtureId: 'f1', homeGoals: 0, awayGoals: 9),
    ];

    final stats = computeTipStats(
      userId: 'me',
      rounds: [_round()],
      tipsByRound: {'r1': tips},
      fixturesById: fixtures,
    );

    expect(stats.scored, 4);
    expect(stats.exact, 1);
    expect(stats.goalDiff, 1);
    expect(stats.tendency, 1);
    expect(stats.missed, 1);
    expect(stats.accuracy, closeTo(0.75, 1e-9));
    // 4 (exakt) + 2 (Tendenz) + 3 (Tordiff) + 0 = 9
    expect(stats.points, 9);
    expect(stats.bestTip, 4);
    expect(stats.rounds, 1);
  });

  test('computeTipStats: leere Eingabe -> Nullbilanz', () {
    final stats = computeTipStats(
      userId: 'me',
      rounds: const [],
      tipsByRound: const {},
      fixturesById: const {},
    );
    expect(stats.scored, 0);
    expect(stats.accuracy, 0);
    expect(stats.rounds, 0);
  });
}
