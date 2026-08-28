import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// Kader-Limits je Position (Migration 0083). Der teure Fehler wäre nicht ein
/// zu strenges Limit, sondern eine Summe **unter** der Kadergröße: Dann findet
/// der Draft irgendwann keinen erlaubten Spieler mehr und beendet sich selbst.
void main() {
  group('Kader-Limits', () {
    test('ohne Limits gilt keine Grenze', () {
      const r = RosterConfig();
      expect(r.limitFor(PlayerPosition.fwd), isNull);
      expect(r.limitsReichenFuerKader(), isTrue);
    });

    test('Limits landen nur in der JSONB, wenn sie gesetzt sind', () {
      expect(const RosterConfig().toJson().containsKey('maxFwd'), isFalse);
      expect(const RosterConfig(maxFwd: 5).toJson()['maxFwd'], 5);
    });

    test('Summe unter der Kadergröße ist ungültig', () {
      // Standardkader: 1+4+4+2+5 = 16 Plätze.
      const r = RosterConfig(maxGk: 2, maxDef: 4, maxMid: 4, maxFwd: 2);
      expect(r.squadSize, 16);
      expect(r.limitsReichenFuerKader(), isFalse);
    });

    test('Summe ab der Kadergröße geht auf', () {
      const r = RosterConfig(maxGk: 2, maxDef: 6, maxMid: 6, maxFwd: 5);
      expect(r.limitsReichenFuerKader(), isTrue);
    });

    test('eine offene Position rettet jede Summe', () {
      // Ohne Grenze im Mittelfeld kann der Kader immer voll werden.
      const r = RosterConfig(maxGk: 1, maxDef: 1, maxFwd: 1);
      expect(r.limitsReichenFuerKader(), isTrue);
    });

    test('withRounds nimmt die Limits mit', () {
      const r = RosterConfig(maxFwd: 5);
      expect(r.withRounds(20).maxFwd, 5);
    });

    test('fromJson liest auch Kommazahlen aus der JSONB', () {
      // Die SQL rechnet in numeric (siehe 0079); ein 5.0 darf nicht werfen.
      final r = RosterConfig.fromJson({'maxFwd': 5.0});
      expect(r.maxFwd, 5);
    });
  });
}
