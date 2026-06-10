import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/data/round_scoring_service.dart';
import 'package:meine_app/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:meine_app/features/fantasy/models/fantasy_models.dart';

FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
        id: id,
        name: name,
        position: pos,
        club: club,
        birthDate: DateTime(1995),
        nationality: 'de');

void main() {
  group('scorePlayer (Kickbase-Stil)', () {
    const scoring = FantasyScoring.kickbaseStyle; // app2 gk/def6 mid5 fwd4 ...

    test('Stürmer mit 2 Toren + Einsatz', () {
      final pts = scorePlayer(const PlayerMatchStats(goals: 2, played: true),
          PlayerPosition.fwd, scoring);
      expect(pts, 2 + 2 * 4); // appearance + 2*goalFwd
    });

    test('Verteidiger-Tor wiegt mehr als Stürmer-Tor', () {
      final def = scorePlayer(const PlayerMatchStats(goals: 1, played: true),
          PlayerPosition.def, scoring);
      final fwd = scorePlayer(const PlayerMatchStats(goals: 1, played: true),
          PlayerPosition.fwd, scoring);
      expect(def, greaterThan(fwd));
    });

    test('Zu-Null nur für Torwart/Abwehr', () {
      expect(
          scorePlayer(const PlayerMatchStats(played: true, cleanSheet: true),
              PlayerPosition.gk, scoring),
          2 + 4);
      expect(
          scorePlayer(const PlayerMatchStats(played: true, cleanSheet: true),
              PlayerPosition.fwd, scoring),
          2); // Zu-Null zählt für Stürmer nicht
    });
  });

  group('bestEleven', () {
    test('wählt je Position die besten und summiert nur die Startelf', () {
      final players = {
        _p('gk1', 'GK1', PlayerPosition.gk, 'C'): 5,
        _p('fwd1', 'FWD1', PlayerPosition.fwd, 'C'): 9,
        _p('fwd2', 'FWD2', PlayerPosition.fwd, 'C'): 7,
        _p('fwd3', 'FWD3', PlayerPosition.fwd, 'C'): 3, // Bank (nur 2 ST-Slots)
      };
      final lineup = bestEleven(players, const RosterConfig());
      expect(lineup.starterIds.contains('fwd3'), isFalse);
      expect(lineup.total, 5 + 9 + 7);
    });
  });

  group('RoundScoringService.computeStats (echte OpenLigaDB-Form)', () {
    test('Tore per Nachname + Zu-Null per Verein', () {
      final pool = [
        _p('seed:4', 'Harry Kane', PlayerPosition.fwd, 'FC Bayern München'),
        _p('seed:1', 'Manuel Neuer', PlayerPosition.gk, 'FC Bayern München'),
        _p('seed:x', 'Florian Wirtz', PlayerPosition.mid, 'Bayer 04 Leverkusen'),
      ];
      final matches = [
        {
          'matchIsFinished': true,
          'team1': {'teamName': 'FC Bayern München'},
          'team2': {'teamName': '1. FC Köln'},
          'matchResults': [
            {'resultTypeID': 2, 'pointsTeam1': 5, 'pointsTeam2': 0},
          ],
          'goals': [
            {'goalGetterName': 'H. Kane', 'isOwnGoal': false},
            {'goalGetterName': 'Kane', 'isOwnGoal': false},
            {'goalGetterName': 'Eigentor', 'isOwnGoal': true},
          ],
        },
      ];
      final stats = RoundScoringService.computeStats(pool: pool, matches: matches);

      expect(stats['seed:4']?.goals, 2); // Kane 2 Tore (Eigentor ignoriert)
      expect(stats['seed:4']?.played, isTrue);
      expect(stats['seed:1']?.cleanSheet, isTrue); // Bayern zu Null -> Neuer
      expect(stats.containsKey('seed:x'), isFalse); // kein Spiel/keine Daten
    });
  });
}
