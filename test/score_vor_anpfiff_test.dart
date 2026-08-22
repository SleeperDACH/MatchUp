import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/match_detail.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/core/util/club_logos.dart';
import 'package:matchup/features/tippspiel/logic/round_table.dart';
import 'package:matchup/features/tippspiel/models/tip.dart';
import 'package:matchup/features/tippspiel/models/tip_round.dart';

const _heim = TeamRef(id: 't1', name: 'LSK Hansa', shortName: 'LSK');
const _gast = TeamRef(id: 't2', name: 'Hansa Rostock', shortName: 'FCH');

Fixture _fixture(FixtureStatus status, {int? home, int? away}) => Fixture(
      id: 'sportmonks:1',
      leagueId: 'dfb_pokal',
      season: 2026,
      round: 1,
      roundName: '1. Runde',
      kickoff: DateTime.utc(2026, 8, 22, 13, 30),
      home: _heim,
      away: _gast,
      status: status,
      homeScore: home,
      awayScore: away,
    );

TeamFixture _teamFixture(FixtureStatus status, {int? home, int? away}) =>
    TeamFixture(
      id: 'sportmonks:1',
      kickoff: DateTime.utc(2026, 8, 22, 13, 30),
      status: status,
      leagueName: 'DFB-Pokal',
      home: _heim,
      away: _gast,
      homeScore: home,
      awayScore: away,
    );

MatchDetail _detail(FixtureStatus status, {int? home, int? away}) => MatchDetail(
      id: 'sportmonks:1',
      kickoff: DateTime.utc(2026, 8, 22, 13, 30),
      status: status,
      home: _heim,
      away: _gast,
      homeScore: home,
      awayScore: away,
      goals: const [],
      lineups: const [],
      stats: const [],
      events: const [],
    );

void main() {
  group('Spielstand erst ab Anpfiff', () {
    // Der Auslöser: Sportmonks führt im `CURRENT`-Eintrag schon vor dem
    // Anstoß ein 0:0. Im Live-Tab stand deshalb „0:0" über Spielen, die erst
    // in Minuten anfingen — dort gehört bis zum Anpfiff die Uhrzeit hin.
    test('angesetztes Spiel mit 0:0 aus dem Feed gilt als ohne Stand', () {
      expect(_fixture(FixtureStatus.scheduled, home: 0, away: 0).hasScore,
          isFalse);
      expect(_teamFixture(FixtureStatus.scheduled, home: 0, away: 0).hasScore,
          isFalse);
      expect(
          _detail(FixtureStatus.scheduled, home: 0, away: 0).hasScore, isFalse);
    });

    test('laufendes Spiel zeigt seinen Stand, auch beim 0:0', () {
      expect(_fixture(FixtureStatus.live, home: 0, away: 0).hasScore, isTrue);
      expect(
          _teamFixture(FixtureStatus.live, home: 0, away: 0).hasScore, isTrue);
      expect(_detail(FixtureStatus.live, home: 0, away: 0).hasScore, isTrue);
    });

    test('beendetes Spiel behält seinen Stand', () {
      expect(_fixture(FixtureStatus.finished, home: 2, away: 1).hasScore,
          isTrue);
      expect(_teamFixture(FixtureStatus.finished, home: 2, away: 1).hasScore,
          isTrue);
      expect(
          _detail(FixtureStatus.finished, home: 2, away: 1).hasScore, isTrue);
    });

    test('ohne Zahlen bleibt es dabei — auch wenn das Spiel läuft', () {
      expect(_fixture(FixtureStatus.live).hasScore, isFalse);
      expect(_fixture(FixtureStatus.scheduled).hasScore, isFalse);
    });

    // Die eigentliche Gefahr saß nicht in der Anzeige: die Live-Wertung
    // nimmt jedes Spiel mit `hasScore` in die Tabelle auf. Ein 0:0 vor dem
    // Anpfiff hätte Punkte für ein Ergebnis verteilt, das es nicht gab.
    test('Live-Wertung zählt ein noch nicht angepfiffenes Spiel nicht', () {
      const anna = RoundMember(userId: 'a', username: 'anna');
      final tips = [
        const MemberTip(
            userId: 'a', fixtureId: 'sportmonks:1', homeGoals: 0, awayGoals: 0),
      ];

      final vorAnpfiff = totalPointsByMember(
        members: const [anna],
        fixtures: [_fixture(FixtureStatus.scheduled, home: 0, away: 0)],
        tips: tips,
        rules: const ScoringRules(),
      );
      expect(vorAnpfiff['a'], 0,
          reason: 'ein 0:0 aus dem Feed ist kein gespieltes Unentschieden');

      final nachAnpfiff = totalPointsByMember(
        members: const [anna],
        fixtures: [_fixture(FixtureStatus.live, home: 0, away: 0)],
        tips: tips,
        rules: const ScoringRules(),
      );
      expect(nachAnpfiff['a'], greaterThan(0),
          reason: 'läuft das Spiel, zählt der exakte Tipp wieder');
    });
  });

  group('Vereinswappen', () {
    // Sportmonks legt unter der Team-ID des Lüneburger SK Hansa dasselbe Bild
    // ab wie unter Hansa Rostock. Der Override zieht das richtige Wappen.
    test('LSK Hansa bekommt nicht das Wappen von Hansa Rostock', () {
      final lsk = clubLogoUrl(
          'LSK Hansa', 'https://cdn.sportmonks.com/images/soccer/teams/0/3744.png');
      final rostock = clubLogoUrl('Hansa Rostock',
          'https://cdn.sportmonks.com/images/soccer/teams/31/575.png');
      expect(lsk, isNot(rostock));
      expect(lsk, contains('thesportsdb.com'));
    });

    test('Vereine ohne Eintrag behalten die Feed-URL', () {
      expect(clubLogoUrl('Hemelingen', 'https://example.test/h.png'),
          'https://example.test/h.png');
      expect(clubLogoUrl('Unbekannt', null), isNull);
    });
  });
}
