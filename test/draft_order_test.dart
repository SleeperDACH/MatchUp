import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/logic/draft_order.dart';
import 'package:meine_app/features/fantasy/models/fantasy_models.dart';

void main() {
  group('snakeSlot — muss der Server-Logik entsprechen', () {
    test('2 Manager: 1,2,2,1,1,2,2,1 (verifiziert im Backend-Test)', () {
      final slots = [for (var p = 0; p < 8; p++) snakeSlot(p, 2)];
      expect(slots, [1, 2, 2, 1, 1, 2, 2, 1]);
    });

    test('3 Manager: Hin 1-2-3, Rück 3-2-1, dann wieder 1-2-3', () {
      final slots = [for (var p = 0; p < 9; p++) snakeSlot(p, 3)];
      expect(slots, [1, 2, 3, 3, 2, 1, 1, 2, 3]);
    });

    test('robuster Fallback ohne Manager', () {
      expect(snakeSlot(0, 0), 1);
    });
  });

  group('currentManager', () {
    final managers = [
      const FantasyManager(userId: 'a', username: 'A', draftPosition: 1),
      const FantasyManager(userId: 'b', username: 'B', draftPosition: 2),
    ];

    test('Pick 0 -> Slot 1, Pick 1 -> Slot 2, Pick 2 -> Slot 2 (Snake)', () {
      expect(currentManager(managers, 0)?.userId, 'a');
      expect(currentManager(managers, 1)?.userId, 'b');
      expect(currentManager(managers, 2)?.userId, 'b');
      expect(currentManager(managers, 3)?.userId, 'a');
    });
  });

  test('totalPicks = Manager × Kadergröße', () {
    expect(totalPicks(2, const RosterConfig()), 32);
  });
}
