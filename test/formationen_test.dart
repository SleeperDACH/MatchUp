import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

String _kurz((int, int, int) f) => '${f.$1}-${f.$2}-${f.$3}';

/// Die wählbaren Formationen ergeben sich aus den Spannen in [RosterConfig] —
/// sie stehen nirgends als Liste. Dieser Test hält fest, welche dabei
/// herauskommen, damit eine Änderung an den Spannen sichtbar wird.
void main() {
  group('Formationen', () {
    test('die Vorgabe erlaubt elf Aufstellungen', () {
      final f = const RosterConfig().validFormations().map(_kurz).toList();
      expect(f, [
        '3-3-4', '3-4-3', '3-5-2', '3-6-1',
        '4-2-4', '4-3-3', '4-4-2', '4-5-1',
        '5-2-3', '5-3-2', '5-4-1',
      ]);
    });

    test('die drei neuen sind genau die, die vorher fehlten', () {
      // Der alte FPL-Zuschnitt: MF bis 5, ST bis 3.
      const alt = RosterConfig(midMax: 5, fwdMax: 3);
      final vorher = alt.validFormations().map(_kurz).toSet();
      final jetzt = const RosterConfig().validFormations().map(_kurz).toSet();
      expect(vorher.length, 8);
      expect(jetzt.difference(vorher), {'3-3-4', '3-6-1', '4-2-4'});
      // Geweitet heißt geweitet: Es fällt nichts weg.
      expect(vorher.difference(jetzt), isEmpty);
    });

    test('jede Formation ergibt genau elf Spieler', () {
      const r = RosterConfig();
      for (final f in r.validFormations()) {
        expect(r.gk + f.$1 + f.$2 + f.$3, r.starters, reason: _kurz(f));
      }
    });

    test('jede Formation gilt auch der Prüfung als gültig', () {
      // Dieselbe Regel prüft der Server (fantasy_set_lineup); wären sich die
      // beiden uneins, böte die App Formationen an, die er ablehnt.
      const r = RosterConfig();
      for (final f in r.validFormations()) {
        expect(
          r.isValidFormation(
              gkCount: r.gk, defCount: f.$1, midCount: f.$2, fwdCount: f.$3),
          isTrue,
          reason: _kurz(f),
        );
      }
    });

    test('ohne Stürmer geht weiterhin nicht', () {
      const r = RosterConfig();
      expect(r.validFormations().any((f) => f.$3 == 0), isFalse);
    });
  });
}
