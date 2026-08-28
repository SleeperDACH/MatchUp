import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/data/stream_dubletten.dart';

/// Der Supabase-Stream kann dieselbe Zeile kurzzeitig zweimal liefern. Was das
/// anrichtete, stand im Kader: 16 Spieler sahen aus wie 17, „Kader voll" kam
/// nach einem sauberen 1:1-Tausch, und der Formationswechsel gab demselben
/// Spieler zwei Plätze.
void main() {
  group('ohneDubletten', () {
    test('behält je Schlüssel die erste Zeile', () {
      final rows = [
        {'league_id': 'l', 'player_id': 'lemke', 'via': 'draft'},
        {'league_id': 'l', 'player_id': 'lemke', 'via': 'trade'},
        {'league_id': 'l', 'player_id': 'kimmich', 'via': 'draft'},
      ];
      final raus = ohneDubletten(rows, ['league_id', 'player_id']);
      expect(raus.length, 2);
      expect(raus.first['via'], 'draft');
    });

    test('zusammengesetzter Schlüssel trennt sauber', () {
      final rows = [
        {'a': '1', 'b': 'x'},
        {'a': '1', 'b': 'y'},
        {'a': '1', 'b': 'x'},
      ];
      expect(ohneDubletten(rows, ['a', 'b']).length, 2);
    });

    test('gleiche Werte sind dieselbe Zeile', () {
      final rows = [
        {'a': 1, 'b': 'x'},
        {'a': 1, 'b': 'x'},
      ];
      expect(ohneDubletten(rows, ['a', 'b']).length, 1);
    });

    test('fehlt ein Schlüssel, bleibt die Zeile stehen', () {
      // Lieber eine Dublette zu viel als eine Zeile zu wenig.
      final rows = [
        {'league_id': 'l'},
        {'league_id': 'l'},
      ];
      expect(ohneDubletten(rows, ['league_id', 'player_id']).length, 2);
    });

    test('leere Eingabe bleibt leer', () {
      expect(ohneDubletten(const [], ['a']), isEmpty);
    });

    test('die Reihenfolge bleibt erhalten', () {
      final rows = [
        {'id': 'c'},
        {'id': 'a'},
        {'id': 'c'},
        {'id': 'b'},
      ];
      expect(
        ohneDubletten(rows, ['id']).map((z) => z['id']).toList(),
        ['c', 'a', 'b'],
      );
    });
  });
}
