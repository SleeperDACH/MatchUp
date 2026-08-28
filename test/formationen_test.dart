import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

String _kurz((int, int, int) f) => '${f.$1}-${f.$2}-${f.$3}';

/// Die wählbaren Formationen ergeben sich aus den Spannen in [RosterConfig] —
/// sie stehen nirgends als Liste. Dieser Test hält fest, welche dabei
/// herauskommen, damit eine Änderung an den Spannen sichtbar wird.
void main() {
  group('Formationen', () {
    test('die Vorgabe erlaubt neun Aufstellungen', () {
      final f = const RosterConfig().validFormations().map(_kurz).toList();
      expect(f, [
        '3-4-3', '3-5-2',
        '4-2-4', '4-3-3', '4-4-2', '4-5-1',
        '5-2-3', '5-3-2', '5-4-1',
      ]);
    });

    test('gegenüber dem FPL-Zuschnitt kommt genau 4-2-4 dazu', () {
      // Der ursprüngliche Zuschnitt: ST bis 3.
      const alt = RosterConfig(fwdMax: 3);
      final vorher = alt.validFormations().map(_kurz).toSet();
      final jetzt = const RosterConfig().validFormations().map(_kurz).toSet();
      expect(vorher.length, 8);
      expect(jetzt.difference(vorher), {'4-2-4'});
      // Und es fällt nichts weg.
      expect(vorher.difference(jetzt), isEmpty);
    });

    test('vier Stürmer nur mit vier Abwehrspielern', () {
      // Die Kopplung, die 3-3-4 aussortiert und 4-2-4 stehen lässt. Reine
      // Min/Max-Spannen könnten das nicht: Beide brauchen fwdMax 4.
      expect(RosterConfig.vierStuermerBrauchenVierAbwehr(4, 4), isTrue);
      expect(RosterConfig.vierStuermerBrauchenVierAbwehr(3, 4), isFalse);
      // Unter vier Stürmern greift die Regel gar nicht.
      expect(RosterConfig.vierStuermerBrauchenVierAbwehr(3, 3), isTrue);

      const r = RosterConfig();
      expect(
          r.isValidFormation(
              gkCount: 1, defCount: 3, midCount: 3, fwdCount: 4),
          isFalse);
      expect(
          r.isValidFormation(
              gkCount: 1, defCount: 4, midCount: 2, fwdCount: 4),
          isTrue);
    });

    test('sechs Mittelfeldspieler gibt es nicht mehr', () {
      expect(const RosterConfig().validFormations().any((f) => f.$2 > 5),
          isFalse);
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
