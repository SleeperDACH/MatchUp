import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/logic/matchup_schedule.dart';

void main() {
  group('roundPairings (Round-Robin, Kreismethode)', () {
    test('weniger als zwei Manager -> keine Paarung', () {
      expect(roundPairings([], 1), isEmpty);
      expect(roundPairings(['a'], 1), isEmpty);
    });

    test('gerade Zahl: jeder gegen jeden genau einmal über n-1 Spieltage', () {
      final ids = ['a', 'b', 'c', 'd'];
      final seen = <String>{};
      for (var r = 1; r <= 3; r++) {
        final pairs = roundPairings(ids, r);
        expect(pairs.length, 2); // 4 Manager -> 2 Paarungen
        for (final m in pairs) {
          expect(m.isBye, isFalse);
          expect(m.home, isNot(m.away));
          final key = ([m.home, m.away!]..sort()).join('-');
          expect(seen.add(key), isTrue, reason: 'Paarung doppelt: $key');
        }
      }
      expect(seen.length, 6); // C(4,2)
    });

    test('ungerade Zahl: pro Spieltag genau ein Bye, je Manager einmal', () {
      final ids = ['a', 'b', 'c'];
      final byes = <String, int>{};
      for (var r = 1; r <= 3; r++) {
        final pairs = roundPairings(ids, r);
        final byeCount = pairs.where((m) => m.isBye).length;
        expect(byeCount, 1);
        for (final m in pairs.where((m) => m.isBye)) {
          byes[m.home] = (byes[m.home] ?? 0) + 1;
        }
      }
      expect(byes.keys.toSet(), {'a', 'b', 'c'});
      expect(byes.values.every((c) => c == 1), isTrue);
    });

    test('Zyklus wiederholt sich nach n-1 Spieltagen', () {
      final ids = ['a', 'b', 'c', 'd'];
      String key(List<Matchup> p) =>
          (p.map((m) => ([m.home, m.away ?? '∅']..sort()).join('-')).toList()
                ..sort())
              .join('|');
      expect(key(roundPairings(ids, 1)), key(roundPairings(ids, 4)));
    });
  });

  group('h2hStandings (Bilanz)', () {
    final ids = ['a', 'b', 'c', 'd']; // Spieltag 1: a-d, b-c

    test('Sieg/Niederlage/Unentschieden und Punkte', () {
      final standings = h2hStandings(ids, {
        1: {'a': 10, 'd': 5, 'b': 7, 'c': 7},
      });
      final byId = {for (final r in standings) r.managerId: r};

      expect(byId['a']!.wins, 1);
      expect(byId['a']!.pointsFor, 10);
      expect(byId['a']!.pointsAgainst, 5);
      expect(byId['d']!.losses, 1);
      expect(byId['b']!.ties, 1);
      expect(byId['c']!.ties, 1);

      // Sieger steht oben.
      expect(standings.first.managerId, 'a');
    });

    test('Bye zählt nicht in die Bilanz', () {
      final standings = h2hStandings(['a', 'b', 'c'], {
        1: {'b': 5, 'c': 3}, // a hat an Spieltag 1 frei
      });
      final byId = {for (final r in standings) r.managerId: r};
      expect(byId['a']!.played, 0);
      expect(byId['b']!.wins, 1);
      expect(byId['c']!.losses, 1);
    });

    test('Sortierung: Siege, dann Differenz, dann erzielte Punkte', () {
      // Zwei Spieltage; b gewinnt beide, a einmal.
      final standings = h2hStandings(ids, {
        1: {'a': 10, 'd': 1, 'b': 9, 'c': 1}, // a & b siegen
        4: {'a': 2, 'd': 9, 'b': 20, 'c': 1}, // d & b siegen
      });
      expect(standings.first.managerId, 'b'); // 2 Siege
    });
  });
}
