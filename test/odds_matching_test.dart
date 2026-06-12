import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/data/odds/match_odds.dart';
import 'package:meine_app/core/data/odds/odds_matching.dart';
import 'package:meine_app/core/data/odds/odds_team_resolver.dart';
import 'package:meine_app/core/models/models.dart';

const _wm = 'soccer_fifa_world_cup';

Fixture _fixture(
  String id, {
  required String homeCode,
  required String awayCode,
  required DateTime kickoff,
}) =>
    Fixture(
      id: id,
      leagueId: 'wm2026',
      season: 2026,
      round: 1,
      roundName: 'Gruppenphase 1',
      kickoff: kickoff,
      home: TeamRef(id: 'h', name: homeCode, shortName: homeCode),
      away: TeamRef(id: 'a', name: awayCode, shortName: awayCode),
      status: FixtureStatus.scheduled,
    );

MatchOdds _odds(
  String home,
  String away, {
  required double h,
  required double d,
  required double a,
  required DateTime time,
}) =>
    MatchOdds(
      homeTeam: home,
      awayTeam: away,
      commenceTime: time,
      homeWin: h,
      draw: d,
      awayWin: a,
      bookmaker: 'Pinnacle',
    );

void main() {
  group('OddsTeamResolver', () {
    test('englische Namen → OpenLigaDB-FIFA-Codes', () {
      expect(OddsTeamResolver.codeFor(_wm, 'Brazil'), 'BRA');
      expect(OddsTeamResolver.codeFor(_wm, 'Switzerland'), 'CHE');
      expect(OddsTeamResolver.codeFor(_wm, 'South Korea'), 'KOR');
    });

    test('Akzente und Schreibvarianten', () {
      expect(OddsTeamResolver.codeFor(_wm, 'Curaçao'), 'CUW');
      expect(OddsTeamResolver.codeFor(_wm, 'Czechia'), 'CZE');
      expect(OddsTeamResolver.codeFor(_wm, 'Türkiye'), 'TUR');
    });

    test('unbekannter Sport-Key liefert null', () {
      expect(OddsTeamResolver.codeFor('soccer_unknown', 'Brazil'), isNull);
    });
  });

  group('matchOdds', () {
    final t = DateTime.utc(2026, 6, 13, 22);

    test('matcht gleiche Heim-/Auswärtsreihenfolge', () {
      final f = _fixture('m1', homeCode: 'BRA', awayCode: 'MAR', kickoff: t);
      final odds = [
        _odds('Brazil', 'Morocco', h: 1.69, d: 3.76, a: 5.58, time: t),
      ];
      final result = matchOdds(_wm, [f], odds);
      expect(result['m1']?.homeWin, 1.69);
      expect(result['m1']?.awayWin, 5.58);
    });

    test('dreht Quote, wenn Quelle Teams andersherum führt', () {
      final f = _fixture('m1', homeCode: 'BRA', awayCode: 'MAR', kickoff: t);
      // Quelle führt Marokko als Heim.
      final odds = [
        _odds('Morocco', 'Brazil', h: 5.58, d: 3.76, a: 1.69, time: t),
      ];
      final result = matchOdds(_wm, [f], odds);
      // Aus Brasilien-Sicht: Heimsieg-Quote = 1.69.
      expect(result['m1']?.homeWin, 1.69);
      expect(result['m1']?.awayWin, 5.58);
    });

    test('kein Match bei weit entferntem Anstoß (Rückspiel-Schutz)', () {
      final f = _fixture('m1', homeCode: 'BRA', awayCode: 'MAR', kickoff: t);
      final odds = [
        _odds('Brazil', 'Morocco',
            h: 1.69, d: 3.76, a: 5.58, time: t.add(const Duration(days: 5))),
      ];
      expect(matchOdds(_wm, [f], odds), isEmpty);
    });

    test('unbekannte Paarung wird übersprungen', () {
      final f = _fixture('m1', homeCode: 'BRA', awayCode: 'MAR', kickoff: t);
      final odds = [
        _odds('Germany', 'Spain', h: 2.0, d: 3.2, a: 3.5, time: t),
      ];
      expect(matchOdds(_wm, [f], odds), isEmpty);
    });
  });
}
