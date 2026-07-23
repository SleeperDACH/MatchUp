import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/logic/bracket.dart';

/// Hilfsfunktion: Endplatzierung als Liste von managerIds (null = offen).
List<String?> _order(PlayoffBracket b) =>
    [for (final p in b.placements) p.managerId];

void main() {
  group('buildPlayoffBracket — 6 Teams, 4 Playoff, 1 Woche', () {
    // Winner-Gruppe [A,B,C,D] → Plätze 1–4; Loser-Gruppe [E,F] → Plätze 5–6.
    const seeding = ['A', 'B', 'C', 'D', 'E', 'F'];

    test('komplett ausgespielt → exakte Endplätze 1–6', () {
      final totals = {
        // Runde 0 (Spieltag 33): Halbfinals + Trost-Finale.
        33: {'A': 100, 'B': 90, 'C': 80, 'D': 70, 'E': 60, 'F': 50},
        // Runde 1 (Spieltag 34): Finale + Spiel um Platz 3.
        34: {'A': 50, 'B': 60, 'C': 30, 'D': 40},
      };
      final b = buildPlayoffBracket(
        seeding: seeding,
        playoffTeams: 4,
        startRound: 33,
        weeksPerRound: 1,
        roundTotals: totals,
        finishedMatchdays: {33, 34},
      );

      expect(b.complete, isTrue);
      // R0: A>D, B>C → Sieger A,B; R1 Finale B>A → 1=B,2=A;
      // Spiel um Platz 3: D>C → 3=D,4=C. Trost: E>F → 5=E,6=F.
      expect(_order(b), ['B', 'A', 'D', 'C', 'E', 'F']);
    });

    test('Winner- und Loser-Bracket haben je die erwartete Rundenzahl', () {
      final b = buildPlayoffBracket(
        seeding: seeding,
        playoffTeams: 4,
        startRound: 33,
        weeksPerRound: 1,
        roundTotals: const {},
        finishedMatchdays: const {},
      );
      // 4 Teams → 2 Runden (Halbfinale, Finale/Platz 3).
      expect(b.winners.length, 2);
      // 2 Teams → 1 Runde (Spiel um Platz 5).
      expect(b.consolation.length, 1);
      expect(b.consolation.first.matches.single.label, 'Spiel um Platz 5');
      expect(b.winners.last.matches.map((m) => m.label),
          containsAll(['Finale', 'Spiel um Platz 3']));
    });

    test('offene Runde → betroffene Plätze bleiben unbestimmt', () {
      final totals = {
        33: {'A': 100, 'B': 90, 'C': 80, 'D': 70, 'E': 60, 'F': 50},
      };
      final b = buildPlayoffBracket(
        seeding: seeding,
        playoffTeams: 4,
        startRound: 33,
        weeksPerRound: 1,
        roundTotals: totals,
        finishedMatchdays: {33}, // Spieltag 34 noch offen
      );
      expect(b.complete, isFalse);
      // Trost-Finale (Spieltag 33) ist entschieden → Plätze 5/6 stehen.
      expect(b.placements[4].managerId, 'E');
      expect(b.placements[5].managerId, 'F');
      // Finale/Platz 3 (Spieltag 34) offen → Plätze 1–4 unbestimmt.
      expect(b.placements[0].managerId, isNull);
    });
  });

  group('Byes (ungerade Playoff-Zahl)', () {
    test('3 Playoff-Teams → Topgesetzter bekommt Freilos, exakte Plätze', () {
      const seeding = ['A', 'B', 'C'];
      final totals = {
        33: {'A': 100, 'B': 90, 'C': 80}, // A hat Freilos; B schlägt C
        34: {'A': 95, 'B': 50}, // Finale A schlägt B; C ist per Bye schon 3.
      };
      final b = buildPlayoffBracket(
        seeding: seeding,
        playoffTeams: 3,
        startRound: 33,
        weeksPerRound: 1,
        roundTotals: totals,
        finishedMatchdays: {33, 34},
      );
      expect(b.complete, isTrue);
      expect(_order(b), ['A', 'B', 'C']);
      // Kein Freilos-Team taucht in der Endtabelle auf.
      expect(b.placements.length, 3);
    });

    test('Gleichstand → höhere Setzung kommt weiter', () {
      const seeding = ['A', 'B'];
      final b = buildPlayoffBracket(
        seeding: seeding,
        playoffTeams: 2,
        startRound: 34,
        weeksPerRound: 1,
        roundTotals: {
          34: {'A': 70, 'B': 70}, // Gleichstand
        },
        finishedMatchdays: {34},
      );
      expect(b.complete, isTrue);
      expect(_order(b), ['A', 'B']); // A (Setzung 1) gewinnt bei Gleichstand
    });
  });

  group('2-Wochen-Partien', () {
    test('Punkte summieren über beide Spieltage', () {
      const seeding = ['A', 'B'];
      final b = buildPlayoffBracket(
        seeding: seeding,
        playoffTeams: 2,
        startRound: 33,
        weeksPerRound: 2,
        roundTotals: {
          33: {'A': 40, 'B': 60},
          34: {'A': 50, 'B': 20}, // A: 90, B: 80 → A gewinnt in Summe
        },
        finishedMatchdays: {33, 34},
      );
      expect(b.complete, isTrue);
      expect(_order(b), ['A', 'B']);
      // Nur ein Spieltag beendet → noch offen.
      final partial = buildPlayoffBracket(
        seeding: seeding,
        playoffTeams: 2,
        startRound: 33,
        weeksPerRound: 2,
        roundTotals: {
          33: {'A': 40, 'B': 60},
        },
        finishedMatchdays: {33},
      );
      expect(partial.complete, isFalse);
    });
  });
}
