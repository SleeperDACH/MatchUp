import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/match_detail_screen.dart';

/// **Jedes Eigentor gehört in den Spielverlauf.**
///
/// Gemeldet an Dortmund gegen HSV: „Das 2:0 fehlt." Es fehlte, weil Sportmonks
/// den Typ als `Own Goal` **mit Leerzeichen** schreibt, der Abgleich aber nur
/// `toLowerCase()` machte und gegen `'owngoal'` prüfte. Aus „Own Goal" wird so
/// „own goal", das traf nie zu, `_iconFor` gab `null` zurück — und der Verlauf
/// filtert genau daran.
///
/// Der Test prüft die Schreibweisen, die die Quelle tatsächlich liefert, plus
/// die naheliegenden Varianten. Er hätte den Fehler beim ersten Durchlauf
/// gefunden.
void main() {
  group('Ereignistypen aus der Quelle werden erkannt', () {
    const gemessen = {
      'Goal': Icons.sports_soccer,
      'Own Goal': Icons.sports_soccer,
      'Yellowcard': Icons.rectangle,
      'Redcard': Icons.rectangle,
      'Substitution': Icons.swap_horiz,
    };

    gemessen.forEach((typ, symbol) {
      test('„$typ" bekommt ein Symbol', () {
        expect(matchEventIcon(typ), symbol,
            reason: 'Ohne Symbol fällt das Ereignis aus dem Verlauf');
      });
    });

    test('Schreibweisen mit Trennern treffen dieselbe Sorte', () {
      // Falls die Quelle morgen anders schreibt, darf nicht dasselbe noch
      // einmal passieren.
      for (final t in ['owngoal', 'own_goal', 'own-goal', 'OWN GOAL']) {
        expect(matchEventIcon(t), Icons.sports_soccer, reason: t);
      }
      for (final t in ['yellowcard', 'Yellow Card', 'yellow_card']) {
        expect(matchEventIcon(t), Icons.rectangle, reason: t);
      }
    });

    test('Unbekanntes bleibt draußen', () {
      expect(matchEventIcon('kickoff'), isNull);
    });
  });
}
