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

    test('Endergebnis vorhanden + Anstoß lange her, kein Haken -> finished', () {
      // OpenLigaDB liefert manchmal das Endergebnis (resultTypeID 2), ohne
      // matchIsFinished zu setzen — nach realistischer Spieldauer (>3 h) darf
      // das Spiel nicht ewig „live" bleiben.
      final stuckLive = Map<String, dynamic>.from(finishedMatch)
        ..['matchIsFinished'] = false
        ..['matchDateTimeUTC'] = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 4))
            .toIso8601String();

      final fixture =
          OpenLigaDbProvider.parseMatch(stuckLive, Leagues.bundesliga, 2025);

      expect(fixture.status, FixtureStatus.finished);
      expect(fixture.homeScore, 5);
      expect(fixture.awayScore, 1);
    });

    test('Endergebnis schon da, aber Spiel läuft noch -> live (WM-Feed)', () {
      // OpenLigaDB pflegt das „Endergebnis" teils schon während des Spiels;
      // kurz nach Anstoß ist es trotzdem LIVE (zählt live in der Tabelle).
      final liveWithResult = Map<String, dynamic>.from(finishedMatch)
        ..['matchIsFinished'] = false
        ..['matchDateTimeUTC'] = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 60))
            .toIso8601String()
        ..['matchResults'] = [
          {'resultTypeID': 1, 'pointsTeam1': 0, 'pointsTeam2': 0},
          {'resultTypeID': 2, 'pointsTeam1': 1, 'pointsTeam2': 2},
        ]
        ..['goals'] = [
          {'scoreTeam1': 1, 'scoreTeam2': 0},
          {'scoreTeam1': 1, 'scoreTeam2': 2},
        ];

      final fixture = OpenLigaDbProvider.parseMatch(
          liveWithResult, Leagues.bundesliga, 2025);

      expect(fixture.status, FixtureStatus.live);
      expect(fixture.homeScore, 1);
      expect(fixture.awayScore, 2);
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

    test('K.-o.: Verlängerung (Typ 4) wird gewertet, nicht reguläre Zeit', () {
      // OpenLigaDB schreibt bei K.-o.-Spielen das Ergebnis nach Verlängerung
      // in Typ 4; Typ 2 ist dort unzuverlässig. Gewertet wird Typ 4.
      final koMatch = Map<String, dynamic>.from(finishedMatch)
        ..['matchResults'] = [
          {'resultTypeID': 1, 'pointsTeam1': 0, 'pointsTeam2': 0},
          {'resultTypeID': 2, 'pointsTeam1': 1, 'pointsTeam2': 1},
          {'resultTypeID': 4, 'pointsTeam1': 2, 'pointsTeam2': 1},
        ];

      final fixture =
          OpenLigaDbProvider.parseMatch(koMatch, Leagues.wm2026, 2026);

      expect(fixture.status, FixtureStatus.finished);
      expect(fixture.homeScore, 2);
      expect(fixture.awayScore, 1);
    });

    test('K.-o.: Elfmeterschießen (Typ 5) zählt nicht', () {
      // 0:0 nach Verlängerung, Sieg im Elfmeterschießen (3:0). Gewertet wird
      // 0:0 (Typ 4), nicht das Elfmeter-Ergebnis (Typ 5) — auch wenn der Feed
      // Typ 5 fälschlich ins Endergebnis (Typ 2) schreibt.
      final penaltyMatch = Map<String, dynamic>.from(finishedMatch)
        ..['matchResults'] = [
          {'resultTypeID': 1, 'pointsTeam1': 0, 'pointsTeam2': 0},
          {'resultTypeID': 2, 'pointsTeam1': 3, 'pointsTeam2': 0},
          {'resultTypeID': 5, 'pointsTeam1': 3, 'pointsTeam2': 0},
          {'resultTypeID': 4, 'pointsTeam1': 0, 'pointsTeam2': 0},
        ];

      final fixture =
          OpenLigaDbProvider.parseMatch(penaltyMatch, Leagues.wm2026, 2026);

      expect(fixture.status, FixtureStatus.finished);
      expect(fixture.homeScore, 0);
      expect(fixture.awayScore, 0);
    });

    test('Gruppenspiel ohne Verlängerung: weiter Endergebnis (Typ 2)', () {
      final fixture = OpenLigaDbProvider.parseMatch(
          finishedMatch, Leagues.bundesliga, 2025);
      expect(fixture.homeScore, 5);
      expect(fixture.awayScore, 1);
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

  group('OpenLigaDbProvider.parseMatchDetail', () {
    Map<String, dynamic> base(List<Map<String, dynamic>> results,
            List<Map<String, dynamic>> goals) =>
        {
          'matchID': 80140,
          'matchDateTimeUTC': '2026-06-22T17:00:00Z',
          'matchIsFinished': true,
          'team1': {'teamId': 1, 'teamName': 'Argentinien', 'shortName': 'ARG'},
          'team2': {'teamId': 2, 'teamName': 'Österreich', 'shortName': 'AUT'},
          'matchResults': results,
          'goals': goals,
          'location': {
            'locationStadium': 'AT&T Stadium',
            'locationCity': 'Dallas',
          },
        };

    test('Ergebnis, Halbzeit, Torschützen-Seite und Flags', () {
      final d = OpenLigaDbProvider.parseMatchDetail(base(
        [
          {'resultTypeID': 1, 'pointsTeam1': 1, 'pointsTeam2': 0},
          {'resultTypeID': 2, 'pointsTeam1': 2, 'pointsTeam2': 1},
        ],
        [
          {
            'matchMinute': 38,
            'goalGetterName': 'Messi',
            'scoreTeam1': 1,
            'scoreTeam2': 0,
          },
          {
            'matchMinute': 60,
            'goalGetterName': 'Gegner',
            'scoreTeam1': 1,
            'scoreTeam2': 1,
            'isPenalty': true,
          },
          {
            'matchMinute': 90,
            'goalGetterName': 'Eigentor',
            'scoreTeam1': 2,
            'scoreTeam2': 1,
            'isOwnGoal': true,
          },
        ],
      ));

      expect(d.status, FixtureStatus.finished);
      expect(d.homeScore, 2);
      expect(d.awayScore, 1);
      expect(d.halfTime, (1, 0));
      expect(d.stadium, 'AT&T Stadium');
      expect(d.city, 'Dallas');
      expect(d.goals.length, 3);
      expect(d.goals[0].scorer, 'Messi');
      expect(d.goals[0].forHomeTeam, isTrue);
      expect(d.goals[1].forHomeTeam, isFalse, reason: 'Auswärts erhöht');
      expect(d.goals[1].penalty, isTrue);
      expect(d.goals[2].forHomeTeam, isTrue);
      expect(d.goals[2].ownGoal, isTrue);
    });

    test('K.-o.: nach Verlängerung maßgeblich, Elfmeter als Zusatz', () {
      final d = OpenLigaDbProvider.parseMatchDetail(base(
        [
          {'resultTypeID': 1, 'pointsTeam1': 0, 'pointsTeam2': 0},
          {'resultTypeID': 2, 'pointsTeam1': 1, 'pointsTeam2': 1},
          {'resultTypeID': 4, 'pointsTeam1': 1, 'pointsTeam2': 1},
          {'resultTypeID': 5, 'pointsTeam1': 4, 'pointsTeam2': 3},
        ],
        const [],
      ));

      expect(d.homeScore, 1);
      expect(d.awayScore, 1);
      expect(d.afterExtraTime, (1, 1));
      expect(d.penalties, (4, 3));
    });
  });
}
