import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/data/openligadb/openligadb_provider.dart';
import 'package:meine_app/core/models/models.dart';

void main() {
  group('OpenLigaDbProvider.parseMatch', () {
    final finishedMatch = <String, dynamic>{
      'matchID': 77554,
      'matchDateTimeUTC': '2026-05-16T13:30:00Z',
      'group': {'groupName': '34. Spieltag', 'groupOrderID': 34},
      'team1': {
        'teamId': 40,
        'teamName': 'FC Bayern München',
        'shortName': 'Bayern',
        'teamIconUrl': 'https://example.com/bayern.svg',
      },
      'team2': {
        'teamId': 65,
        'teamName': '1. FC Köln',
        'shortName': 'Köln',
        'teamIconUrl': 'https://example.com/koeln.svg',
      },
      'matchIsFinished': true,
      'matchResults': [
        {'resultTypeID': 1, 'pointsTeam1': 3, 'pointsTeam2': 1},
        {'resultTypeID': 2, 'pointsTeam1': 5, 'pointsTeam2': 1},
      ],
      'goals': <dynamic>[],
    };

    test('beendetes Spiel: Endergebnis (resultTypeID 2), nicht Halbzeit', () {
      final fixture = OpenLigaDbProvider.parseMatch(
          finishedMatch, Leagues.bundesliga, 2025);

      expect(fixture.id, 'openligadb:77554');
      expect(fixture.leagueId, 'bundesliga');
      expect(fixture.round, 34);
      expect(fixture.status, FixtureStatus.finished);
      expect(fixture.homeScore, 5);
      expect(fixture.awayScore, 1);
      expect(fixture.home.shortName, 'Bayern');
      expect(fixture.away.name, '1. FC Köln');
      expect(fixture.kickoff.isUtc, isTrue);
    });

    test('Endergebnis vorhanden, aber „beendet"-Haken fehlt -> finished', () {
      // OpenLigaDB liefert manchmal das Endergebnis (resultTypeID 2),
      // ohne matchIsFinished zu setzen — darf nicht ewig „live" bleiben.
      final stuckLive = Map<String, dynamic>.from(finishedMatch)
        ..['matchIsFinished'] = false
        ..['matchDateTimeUTC'] = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 2))
            .toIso8601String();

      final fixture =
          OpenLigaDbProvider.parseMatch(stuckLive, Leagues.bundesliga, 2025);

      expect(fixture.status, FixtureStatus.finished);
      expect(fixture.homeScore, 5);
      expect(fixture.awayScore, 1);
    });

    test('zukünftiges Spiel ohne Ergebnis ist scheduled', () {
      final future = Map<String, dynamic>.from(finishedMatch)
        ..['matchIsFinished'] = false
        ..['matchResults'] = <dynamic>[]
        ..['matchDateTimeUTC'] =
            DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String();

      final fixture =
          OpenLigaDbProvider.parseMatch(future, Leagues.bundesliga, 2025);

      expect(fixture.status, FixtureStatus.scheduled);
      expect(fixture.homeScore, isNull);
      expect(fixture.hasStarted, isFalse);
    });

    test('laufendes Spiel: Status live, Spielstand aus Torliste', () {
      final live = Map<String, dynamic>.from(finishedMatch)
        ..['matchIsFinished'] = false
        ..['matchResults'] = <dynamic>[]
        ..['matchDateTimeUTC'] = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 30))
            .toIso8601String()
        ..['goals'] = [
          {'scoreTeam1': 1, 'scoreTeam2': 0},
          {'scoreTeam1': 1, 'scoreTeam2': 1},
        ];

      final fixture =
          OpenLigaDbProvider.parseMatch(live, Leagues.bundesliga, 2025);

      expect(fixture.status, FixtureStatus.live);
      expect(fixture.homeScore, 1);
      expect(fixture.awayScore, 1);
    });

    test('laufendes Spiel ohne Tore steht 0:0 (für Live-Wertung)', () {
      final live = Map<String, dynamic>.from(finishedMatch)
        ..['matchIsFinished'] = false
        ..['matchResults'] = <dynamic>[]
        ..['matchDateTimeUTC'] = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 10))
            .toIso8601String()
        ..['goals'] = <dynamic>[];

      final fixture =
          OpenLigaDbProvider.parseMatch(live, Leagues.bundesliga, 2025);

      expect(fixture.status, FixtureStatus.live);
      expect(fixture.homeScore, 0);
      expect(fixture.awayScore, 0);
      expect(fixture.hasScore, isTrue);
    });

    test('geplantes Spiel bleibt ohne Spielstand', () {
      final scheduled = Map<String, dynamic>.from(finishedMatch)
        ..['matchIsFinished'] = false
        ..['matchResults'] = <dynamic>[]
        ..['matchDateTimeUTC'] = DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .toIso8601String()
        ..['goals'] = <dynamic>[];

      final fixture =
          OpenLigaDbProvider.parseMatch(scheduled, Leagues.bundesliga, 2025);

      expect(fixture.status, FixtureStatus.scheduled);
      expect(fixture.hasScore, isFalse);
    });

    test('leerer shortName fällt auf teamName zurück', () {
      final match = Map<String, dynamic>.from(finishedMatch)
        ..['team1'] = {
          'teamId': 40,
          'teamName': 'FC Bayern München',
          'shortName': '',
          'teamIconUrl': null,
        };

      final fixture =
          OpenLigaDbProvider.parseMatch(match, Leagues.bundesliga, 2025);

      expect(fixture.home.shortName, 'FC Bayern München');
    });
  });
}
