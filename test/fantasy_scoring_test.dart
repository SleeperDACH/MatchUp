import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/data/round_scoring_service.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
        id: id,
        name: name,
        position: pos,
        club: club,
        birthDate: DateTime(1995),
        nationality: 'de');

void main() {
  // Die Referenzwerte stammen aus scoring/test/scoring.test.ts — beide
  // Implementierungen derselben Punktevergabe müssen identisch rechnen.
  group('scorePlayer (Voll-Advanced, Referenz aus dem TS-Modul)', () {
    test('Einsatzstufen: exakte Werte je Minuten', () {
      // **`goalsConceded: 1` isoliert die Einsatzstufe.** Seit das
      // Mittelfeld 4 Punkte für die Null hinten bekommt, bringt ein Datensatz
      // ohne Gegentor ab 60 Minuten zusätzlich diesen Bonus — der Test würde
      // dann nicht mehr messen, was sein Name sagt. Ein Gegentor ist für das
      // Mittelfeld selbst mit 0 bewertet, stört also nichts.
      double m(int min) => scorePlayer(
          PlayerMatchStats(minutes: min, goalsConceded: 1),
          PlayerPosition.mid);
      expect(m(0), 0);
      expect(m(10), 2);
      expect(m(45), 4);
      expect(m(75), 6);
      expect(m(90), 10);
    });

    test('MID: 90 Min + 1 Tor = 25', () {
      expect(
          scorePlayer(
              const PlayerMatchStats(
                  minutes: 90, goals: 1, goalsConceded: 1),
              PlayerPosition.mid),
          25);
    });

    test('MID bekommt 4 für die Null hinten', () {
      // Neu: Vorher ging das Mittelfeld leer aus, obwohl ein defensiver
      // Sechser sie mit erarbeitet. Abwehr und Torwart bekommen weiter 12.
      const s = PlayerMatchStats(minutes: 90, goalsConceded: 0);
      expect(scorePlayer(s, PlayerPosition.mid), 14, reason: '10 + 4');
      expect(scorePlayer(s, PlayerPosition.def), 22, reason: '10 + 12');
      expect(scorePlayer(s, PlayerPosition.fwd), 10, reason: 'nichts');
    });

    test('GK: 90 Min, 3 Paraden, 1 Gegentor, Rating 6.8 = 15', () {
      expect(
          scorePlayer(
              const PlayerMatchStats(
                  minutes: 90, saves: 3, goalsConceded: 1, rating: 6.8),
              PlayerPosition.gk),
          15);
    });

    test('FWD: 60 Min + 1 Tor + Rating 6.5 = 21', () {
      expect(
          scorePlayer(
              const PlayerMatchStats(minutes: 60, goals: 1, rating: 6.5),
              PlayerPosition.fwd),
          21);
    });

    test('Elfmetertor zählt 12, reguläres Tor 15 — nicht doppelt', () {
      final r = scorePlayerDetailed(
          const PlayerMatchStats(minutes: 90, goals: 2, penaltyGoals: 1),
          PlayerPosition.fwd);
      final tor = r.breakdown.firstWhere((l) => l.label == 'Tor');
      final elfer = r.breakdown.firstWhere((l) => l.label == 'Tor (Elfmeter)');
      expect(tor.count, 1, reason: 'nur das nicht-Elfmeter-Tor');
      expect(elfer.subtotal, 12);
      expect(r.total, 10 + 15 + 12);
    });

    test('Key Pass zählt Großchancen nicht doppelt', () {
      final r = scorePlayerDetailed(
          const PlayerMatchStats(
              minutes: 90, keyPasses: 4, bigChancesCreated: 1),
          PlayerPosition.mid);
      final kp = r.breakdown.firstWhere((l) => l.label == 'Key Pass');
      expect(kp.count, 3);
    });

    test('Zu Null erst ab 60 Minuten und nur ohne Gegentor', () {
      double cs(int min, int conceded) => scorePlayerDetailed(
              PlayerMatchStats(minutes: min, goalsConceded: conceded),
              PlayerPosition.def)
          .breakdown
          .where((l) => l.label == 'Zu Null')
          .fold(0.0, (a, l) => a + l.subtotal);
      expect(cs(90, 0), 12);
      expect(cs(59, 0), 0, reason: 'unter der Mindestspielzeit');
      expect(cs(90, 1), 0, reason: 'Gegentor schließt Zu Null aus');
    });

    test('Zu Null zählt für Mittelfeld und Sturm nicht', () {
      expect(
          scorePlayer(const PlayerMatchStats(minutes: 90), PlayerPosition.fwd),
          10);
    });

    test('Paraden-Meilensteine sind kumulativ', () {
      expect(reachedMilestones(4, FantasyScoringRules.standard.saveMilestones),
          isEmpty);
      expect(
          reachedMilestones(5, FantasyScoringRules.standard.saveMilestones)
              .fold(0.0, (a, m) => a + m.bonus),
          8);
      expect(
          reachedMilestones(8, FantasyScoringRules.standard.saveMilestones)
              .fold(0.0, (a, m) => a + m.bonus),
          20);
    });

    test('Rating null löst keinen Malus aus', () {
      final ohne = scorePlayerDetailed(
          const PlayerMatchStats(minutes: 90), PlayerPosition.mid);
      expect(ohne.breakdown.where((l) => l.label.startsWith('Rating')), isEmpty);
      final schlecht = scorePlayerDetailed(
          const PlayerMatchStats(minutes: 90, rating: 4.5), PlayerPosition.mid);
      expect(schlecht.total, lessThan(ohne.total));
    });

    test('Katastrophenspiel wird klar negativ', () {
      final pts = scorePlayer(
          const PlayerMatchStats(
              minutes: 90,
              goalsConceded: 5,
              ownGoals: 1,
              red: 1,
              rating: 3.5),
          PlayerPosition.gk);
      expect(pts, lessThan(0));
    });

    test('Bruchteile summieren korrekt (Key Pass 1,5 / Foul −0,4)', () {
      // Gegentor gesetzt, damit die Null hinten die Rechnung nicht verdeckt.
      final pts = scorePlayer(
          const PlayerMatchStats(
              minutes: 90, keyPasses: 1, fouls: 1, goalsConceded: 1),
          PlayerPosition.mid);
      expect(pts, closeTo(10 + 1.5 - 0.4, 1e-9));
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

  group('bestEleven (flexible Formation)', () {
    // Voller Kader, sodass eine gültige Formation (FPL: ABW 3–5, MF 2–5,
    // ST 1–3, Summe 11) gebildet werden kann.
    Map<FantasyPlayer, double> squad(Map<String, int> defs,
        Map<String, int> mids, Map<String, int> fwds, int gkPts) {
      final m = <FantasyPlayer, double>{
        _p('gk1', 'GK1', PlayerPosition.gk, 'C'): gkPts.toDouble(),
      };
      defs.forEach(
          (id, p) => m[_p(id, id, PlayerPosition.def, 'C')] = p.toDouble());
      mids.forEach(
          (id, p) => m[_p(id, id, PlayerPosition.mid, 'C')] = p.toDouble());
      fwds.forEach(
          (id, p) => m[_p(id, id, PlayerPosition.fwd, 'C')] = p.toDouble());
      return m;
    }

    int posCount(Lineup l, Map<FantasyPlayer, double> all, PlayerPosition pos) =>
        all.keys
            .where((p) => l.starterIds.contains(p.id) && p.position == pos)
            .length;

    test('wählt die punktbeste gültige Formation (hier 3-4-3)', () {
      final players = squad(
        {'d1': 10, 'd2': 9, 'd3': 8, 'd4': 1, 'd5': 1},
        {'m1': 10, 'm2': 9, 'm3': 8, 'm4': 7, 'm5': 1},
        {'f1': 10, 'f2': 9, 'f3': 8},
        5,
      );
      final lineup = bestEleven(players, const RosterConfig());
      expect(lineup.starterIds.length, 11);
      expect(posCount(lineup, players, PlayerPosition.gk), 1);
      expect(posCount(lineup, players, PlayerPosition.def), 3);
      expect(posCount(lineup, players, PlayerPosition.mid), 4);
      expect(posCount(lineup, players, PlayerPosition.fwd), 3);
      // 3-4-3: gk5 + (10+9+8) + (10+9+8+7) + (10+9+8)
      expect(lineup.total, 5 + 27 + 34 + 27);
    });

    test('respektiert die Untergrenze (mind. 3 ABW, auch wenn schwächer)', () {
      // Viele starke MF, schwache ABW: trotzdem müssen 3 ABW ran.
      final players = squad(
        {'d1': 2, 'd2': 2, 'd3': 2},
        {'m1': 9, 'm2': 9, 'm3': 9, 'm4': 9, 'm5': 9},
        {'f1': 9, 'f2': 9},
        5,
      );
      final lineup = bestEleven(players, const RosterConfig());
      expect(posCount(lineup, players, PlayerPosition.def), 3);
      expect(posCount(lineup, players, PlayerPosition.mid), 5);
      expect(posCount(lineup, players, PlayerPosition.fwd), 2);
      expect(lineup.starterIds.length, 11);
    });
  });

  group('chosenLineup / effectiveLineup (manuelle Aufstellung)', () {
    final gk = _p('gk1', 'GK1', PlayerPosition.gk, 'C');
    final fwd1 = _p('fwd1', 'FWD1', PlayerPosition.fwd, 'C');
    final fwd2 = _p('fwd2', 'FWD2', PlayerPosition.fwd, 'C');
    final fwd3 = _p('fwd3', 'FWD3', PlayerPosition.fwd, 'C');
    final points = <FantasyPlayer, double>{
      gk: 5,
      fwd1: 9,
      fwd2: 7,
      fwd3: 3
    };

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
      // Degenerierter Kader (nur TW + 3 ST) -> keine gültige Formation
      // möglich, Fallback füllt best effort bis zum Positions-Maximum (ST 3).
      final auto = effectiveLineup(points, const RosterConfig(), null);
      final autoEmpty = effectiveLineup(points, const RosterConfig(), const {});
      expect(auto.total, 5 + 9 + 7 + 3);
      expect(autoEmpty.total, 5 + 9 + 7 + 3);
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

  group('Kaderlimit', () {
    // Kleiner Kader: 1-1-1-1 ohne Bank -> Limit 4 Spieler.
    const roster = RosterConfig(gk: 1, def: 1, mid: 1, fwd: 1, bench: 0);
    final players = {
      's:gk': _p('s:gk', 'TW', PlayerPosition.gk, 'A'),
      's:df': _p('s:df', 'ABW', PlayerPosition.def, 'A'),
      's:mf': _p('s:mf', 'MF', PlayerPosition.mid, 'A'),
      's:fw': _p('s:fw', 'ST', PlayerPosition.fwd, 'A'),
      's:x': _p('s:x', 'Extra', PlayerPosition.mid, 'A'),
    };
    final stats = {
      for (final id in players.keys)
        id: const PlayerMatchStats(goals: 1, played: true),
    };
    List<RosterEntry> rosterOf(List<String> ids) => [
          for (final id in ids)
            RosterEntry(managerId: 'u1', playerId: id, acquiredVia: 'draft'),
        ];

    test('über dem Limit -> 0 Punkte', () {
      final over = rosterOf(['s:gk', 's:df', 's:mf', 's:fw', 's:x']); // 5 > 4
      expect(isRosterOverLimit('u1', over, roster), isTrue);
      final totals = effectiveTotalsForRound(
        stats: stats,
        round: 1,
        managers: const [FantasyManager(userId: 'u1', username: 'U1')],
        roster: over,
        playerById: players,
        lineups: const [],
        scoring: FantasyScoringRules.standard,
        rosterConfig: roster,
      );
      expect(totals['u1'], 0);
    });

    test('im Limit -> normale Punkte', () {
      final ok = rosterOf(['s:gk', 's:df', 's:mf', 's:fw']); // 4 == 4
      expect(isRosterOverLimit('u1', ok, roster), isFalse);
      final totals = effectiveTotalsForRound(
        stats: stats,
        round: 1,
        managers: const [FantasyManager(userId: 'u1', username: 'U1')],
        roster: ok,
        playerById: players,
        lineups: const [],
        scoring: FantasyScoringRules.standard,
        rosterConfig: roster,
      );
      expect(totals['u1'], greaterThan(0));
    });
  });
}
