import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/logic/playoff.dart';

void main() {
  group('playoffRounds', () {
    test('halbiert das Feld, ungerade rundet auf (Freilos)', () {
      expect(playoffRounds(2), 1);
      expect(playoffRounds(3), 2);
      expect(playoffRounds(4), 2);
      expect(playoffRounds(5), 3);
      expect(playoffRounds(6), 3);
      expect(playoffRounds(8), 3);
    });
  });

  group('computePlayoffPlan (34 Spieltage)', () {
    test('4 Teams, 1 Woche, Deadline 5 Spieltage vorher', () {
      final p = computePlayoffPlan(
          teams: 4, weeksPerRound: 1, tradeDeadlineOffset: 5);
      expect(p.rounds, 2); // Halbfinale + Finale
      expect(p.startRound, 33); // 34 - 2 + 1
      expect(p.tradeDeadlineRound, 28);
      expect(p.topSeedBye, isFalse);
      expect(p.isValid, isTrue);
    });

    test('6 Teams, 2 Wochen', () {
      final p = computePlayoffPlan(
          teams: 6, weeksPerRound: 2, tradeDeadlineOffset: 5);
      expect(p.rounds, 3);
      expect(p.startRound, 29); // 34 - 6 + 1
      expect(p.tradeDeadlineRound, 24);
    });

    test('ungerade Teamzahl -> Platz 1 bekommt Freilos', () {
      final p = computePlayoffPlan(
          teams: 5, weeksPerRound: 1, tradeDeadlineOffset: 7);
      expect(p.topSeedBye, isTrue);
      expect(p.rounds, 3);
      expect(p.startRound, 32);
      expect(p.tradeDeadlineRound, 25);
    });

    test('zu viele Teams/Wochen -> ungültig', () {
      final p = computePlayoffPlan(
          teams: 8, weeksPerRound: 2, tradeDeadlineOffset: 10);
      // 3 Runden * 2 Wochen = 6 -> Start 29, Deadline 19 -> gültig
      expect(p.isValid, isTrue);
      final bad = computePlayoffPlan(
          teams: 8, weeksPerRound: 2, tradeDeadlineOffset: 10, totalMatchdays: 12);
      expect(bad.isValid, isFalse);
    });
  });
}
