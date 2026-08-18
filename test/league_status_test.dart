import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/league_status.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

FantasyLeague _liga({
  DraftStatus status = DraftStatus.setup,
  int picksMade = 0,
  int? maxTeams,
}) =>
    FantasyLeague(
      id: 'l1',
      name: 'Testliga',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.m1,
      scoring: FantasyScoringRules.standard,
      roster: const RosterConfig(),
      inviteCode: 'ABC',
      draftStatus: status,
      createdBy: 'u1',
      picksMade: picksMade,
      maxTeams: maxTeams,
    );

void main() {
  test('Setup mit freien Plätzen ist offen — ohne Teamzahl', () {
    final s = fantasyStatus(_liga(maxTeams: 10), teams: 3);
    expect(s.label, 'Offen');
    expect(s.detail, isNull);
    expect(s.tone, LeagueStatusTone.wartet);
  });

  test('Laufender Draft zeigt den nächsten Pick, nicht den letzten', () {
    final s = fantasyStatus(_liga(status: DraftStatus.drafting, picksMade: 13));
    expect(s.label, 'Draft läuft');
    expect(s.detail, 'Pick 14');
    expect(s.tone, LeagueStatusTone.laeuft);
  });

  test('Volle Setup-Liga ist startklar', () {
    final s = fantasyStatus(_liga(maxTeams: 8), teams: 8);
    expect(s.label, 'Startklar');
  });

  test('Fertiger Draft meldet den Kader, ohne Zahlen', () {
    final s = fantasyStatus(_liga(status: DraftStatus.done), teams: 8);
    expect(s.label, 'Kader steht');
    expect(s.detail, isNull);
  });

  test('Ohne geladene Managerzahl gilt die Liga als offen', () {
    expect(fantasyStatus(_liga(maxTeams: 10)).label, 'Offen');
  });
}
