import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:meine_app/features/fantasy/logic/weekly_recap.dart';
import 'package:meine_app/features/fantasy/models/fantasy_models.dart';

/// Kleiner Kader-Generator: pro Manager 1 TW, 4 ABW, 4 MF, 2 ST + 5 Bank
/// (Standard-RosterConfig), damit `bestEleven` immer eine gültige 11 findet.
List<FantasyPlayer> _squad(String prefix) {
  final players = <FantasyPlayer>[];
  void add(PlayerPosition pos, int n) {
    for (var i = 0; i < n; i++) {
      players.add(FantasyPlayer(
        id: '$prefix-${pos.name}$i',
        name: '$prefix ${pos.short}$i',
        position: pos,
        club: 'Verein',
        birthDate: DateTime(1995, 1, 1),
        nationality: 'de',
      ));
    }
  }

  add(PlayerPosition.gk, 1);
  add(PlayerPosition.def, 5);
  add(PlayerPosition.mid, 5);
  add(PlayerPosition.fwd, 5);
  return players;
}

void main() {
  const scoring = FantasyScoring.kickbaseStyle;
  const roster = RosterConfig.standard;

  // Zwei Manager mit vollständigem Kader.
  final aSquad = _squad('a');
  final bSquad = _squad('b');
  final playerById = {for (final p in [...aSquad, ...bSquad]) p.id: p};
  final rosterEntries = [
    for (final p in aSquad)
      RosterEntry(managerId: 'a', playerId: p.id, acquiredVia: 'draft'),
    for (final p in bSquad)
      RosterEntry(managerId: 'b', playerId: p.id, acquiredVia: 'draft'),
  ];

  /// Alle Spieler „aufgelaufen" (Grundpunkte) + gezielte Tore.
  Map<String, PlayerMatchStats> statsWithGoals(Map<String, int> goals) => {
        for (final p in playerById.values)
          p.id: PlayerMatchStats(played: true, goals: goals[p.id] ?? 0),
      };

  group('computeWeeklyRecap – Grundfälle', () {
    test('ohne Stats: kein hasData, keine Spieler-Awards', () {
      final recap = computeWeeklyRecap(
        round: 1,
        ids: ['a', 'b'],
        roster: rosterEntries,
        playerById: playerById,
        lineups: const [],
        stats: const {},
        scoring: scoring,
        rosterConfig: roster,
      );
      expect(recap.hasData, isFalse);
      expect(recap.mvp, isNull);
      expect(recap.benchHero, isNull);
      expect(recap.closestWin, isNull);
      expect(recap.ranking.length, 2);
      expect(recap.ranking.every((s) => s.points == 0), isTrue);
    });

    test('Team der Woche = höchstes Ergebnis, Griff ins Klo = niedrigstes', () {
      // a hat einen zusätzlichen Stürmer-Treffer -> mehr Punkte als b.
      final recap = computeWeeklyRecap(
        round: 1,
        ids: ['a', 'b'],
        roster: rosterEntries,
        playerById: playerById,
        lineups: const [],
        stats: statsWithGoals({'a-fwd0': 3}),
        scoring: scoring,
        rosterConfig: roster,
      );
      expect(recap.hasData, isTrue);
      expect(recap.topScore!.managerId, 'a');
      expect(recap.lowScore!.managerId, 'b');
      expect(recap.topScore!.points, greaterThan(recap.lowScore!.points));
    });
  });

  group('MVP & Bank-Held', () {
    test('MVP ist der punktbeste Starter, Bank-Held der beste Nicht-Starter',
        () {
      // b hat vier treffende Stürmer: fwd0..2 je 3 Tore (14 Pkt, Startelf),
      // fwd3 mit 2 Toren (12 Pkt). Da max. 3 Stürmer starten, fällt fwd3 in
      // der besten Elf auf die Bank -> Bank-Held. MVP ist mit 14 Pkt bei
      // Gleichstand der kleinste Spieler-ID: a-fwd0.
      final recap = computeWeeklyRecap(
        round: 1,
        ids: ['a', 'b'],
        roster: rosterEntries,
        playerById: playerById,
        lineups: const [],
        stats: statsWithGoals(
            {'a-fwd0': 3, 'b-fwd0': 3, 'b-fwd1': 3, 'b-fwd2': 3, 'b-fwd3': 2}),
        scoring: scoring,
        rosterConfig: roster,
      );
      expect(recap.mvp!.playerId, 'a-fwd0');
      expect(recap.mvp!.managerId, 'a');
      // 2 (Einsatz) + 3*4 (ST-Tore) = 14
      expect(recap.mvp!.points, 14);

      // fwd3: 2 (Einsatz) + 2*4 = 10 -> bester Bankspieler der Liga.
      expect(recap.benchHero!.playerId, 'b-fwd3');
      expect(recap.benchHero!.managerId, 'b');
      expect(recap.benchHero!.points, 10);
    });
  });

  group('Nervenkrimi & Klatsche', () {
    test('bei einem entschiedenen Spiel sind knappster = deutlichster Sieg',
        () {
      final recap = computeWeeklyRecap(
        round: 1,
        ids: ['a', 'b'],
        roster: rosterEntries,
        playerById: playerById,
        lineups: const [],
        stats: statsWithGoals({'a-fwd0': 1}),
        scoring: scoring,
        rosterConfig: roster,
      );
      expect(recap.closestWin, isNotNull);
      expect(recap.closestWin!.winnerId, 'a');
      expect(recap.closestWin!.loserId, 'b');
      expect(recap.blowout!.winnerId, 'a');
      expect(recap.closestWin!.margin, recap.blowout!.margin);
    });

    test('Gleichstand liefert keinen Sieger', () {
      final recap = computeWeeklyRecap(
        round: 1,
        ids: ['a', 'b'],
        roster: rosterEntries,
        playerById: playerById,
        lineups: const [],
        stats: statsWithGoals(const {}), // beide gleich
        scoring: scoring,
        rosterConfig: roster,
      );
      expect(recap.closestWin, isNull);
      expect(recap.blowout, isNull);
    });
  });

  group('Vergeigte Bank', () {
    test('suboptimale manuelle Aufstellung lässt Punkte auf der Bank', () {
      // a stellt bewusst seinen Toptorschützen (a-fwd0, 3 Tore) auf die Bank:
      // manuelle Startelf ohne ihn, dafür der punktschwache a-fwd1.
      final starters = <String>{
        'a-gk0',
        'a-def0', 'a-def1', 'a-def2', 'a-def3',
        'a-mid0', 'a-mid1', 'a-mid2', 'a-mid3',
        'a-fwd1', 'a-fwd2', // fwd0 fehlt bewusst
      };
      final recap = computeWeeklyRecap(
        round: 1,
        ids: ['a', 'b'],
        roster: rosterEntries,
        playerById: playerById,
        lineups: [
          FantasyLineup(managerId: 'a', round: 1, playerIds: starters),
        ],
        stats: statsWithGoals({'a-fwd0': 3}),
        scoring: scoring,
        rosterConfig: roster,
      );
      expect(recap.benchBlunder, isNotNull);
      expect(recap.benchBlunder!.managerId, 'a');
      // Entgangen: 3 Tore * 4 (ST) = 12 mehr als der Ersatz ohne Tore.
      expect(recap.benchBlunder!.pointsLeft, 12);
    });

    test('optimale Aufstellung -> kein Bank-Blunder', () {
      final recap = computeWeeklyRecap(
        round: 1,
        ids: ['a', 'b'],
        roster: rosterEntries,
        playerById: playerById,
        lineups: const [],
        stats: statsWithGoals({'a-fwd0': 3}),
        scoring: scoring,
        rosterConfig: roster,
      );
      expect(recap.benchBlunder, isNull);
    });
  });
}
