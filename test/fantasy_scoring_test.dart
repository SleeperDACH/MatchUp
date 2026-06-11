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

    test('Assists und Karten fließen ein (voller Feed)', () {
      final pts = scorePlayer(
          const PlayerMatchStats(
              played: true, assists: 2, yellow: 1, minutes: 90),
          PlayerPosition.mid,
          scoring);
      // appearance 2 + 2*assist(3) + 1*yellow(-1)
      expect(pts, 2 + 2 * 3 - 1);
    });
  });

  group('PlayerMatchStats.fromDb (Stats-Feed-Zeile)', () {
    test('liest alle Felder; appeared steuert played', () {
      final s = PlayerMatchStats.fromDb({
        'goals': 1,
        'assists': 2,
        'minutes': 90,
        'yellow': 1,
        'red': 0,
        'clean_sheet': true,
        'appeared': true,
      });
      expect(s.goals, 1);
      expect(s.assists, 2);
      expect(s.minutes, 90);
      expect(s.yellow, 1);
      expect(s.cleanSheet, isTrue);
      expect(s.played, isTrue);
    });

    test('played-Fallback aus Toren/Minuten, wenn appeared fehlt', () {
      expect(PlayerMatchStats.fromDb({'goals': 1}).played, isTrue);
      expect(PlayerMatchStats.fromDb({'minutes': 45}).played, isTrue);
      expect(PlayerMatchStats.fromDb({'goals': 0, 'minutes': 0}).played, isFalse);
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

  group('chosenLineup / effectiveLineup (manuelle Aufstellung)', () {
    final gk = _p('gk1', 'GK1', PlayerPosition.gk, 'C');
    final fwd1 = _p('fwd1', 'FWD1', PlayerPosition.fwd, 'C');
    final fwd2 = _p('fwd2', 'FWD2', PlayerPosition.fwd, 'C');
    final fwd3 = _p('fwd3', 'FWD3', PlayerPosition.fwd, 'C');
    final points = {gk: 5, fwd1: 9, fwd2: 7, fwd3: 3};

    test('chosenLineup summiert genau die gewählten Spieler', () {
      final lineup = chosenLineup(points, {'gk1', 'fwd3'});
      expect(lineup.starterIds, {'gk1', 'fwd3'});
      expect(lineup.total, 5 + 3);
    });

    test('chosenLineup ignoriert Spieler ohne Kader-/Punkteeintrag', () {
      final lineup = chosenLineup(points, {'fwd1', 'weg'});
      expect(lineup.starterIds, {'fwd1'});
      expect(lineup.total, 9);
    });

    test('effectiveLineup: manuelle Wahl schlägt beste Elf', () {
      // Manuell die schwächeren Stürmer aufstellen.
      final manual = effectiveLineup(points, const RosterConfig(),
          {'gk1', 'fwd2', 'fwd3'});
      expect(manual.total, 5 + 7 + 3);
    });

    test('effectiveLineup: ohne Wahl automatisch beste Elf', () {
      final auto = effectiveLineup(points, const RosterConfig(), null);
      final autoEmpty = effectiveLineup(points, const RosterConfig(), const {});
      expect(auto.total, 5 + 9 + 7); // fwd3 ist Bank
      expect(autoEmpty.total, 5 + 9 + 7);
    });
  });

  group('FantasyLineup.fromJson', () {
    test('liest player_ids als Set', () {
      final l = FantasyLineup.fromJson({
        'manager_id': 'm1',
        'round': 7,
        'player_ids': ['seed:1', 'seed:2'],
      });
      expect(l.round, 7);
      expect(l.playerIds, {'seed:1', 'seed:2'});
    });

    test('leere/fehlende player_ids -> leeres Set', () {
      final l = FantasyLineup.fromJson({'manager_id': 'm1', 'round': 1});
      expect(l.playerIds, isEmpty);
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
