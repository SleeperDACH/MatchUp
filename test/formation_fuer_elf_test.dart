import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/formation_fuer_elf.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Nach einem Drop bleibt die Lücke, wo sie entstanden ist.**
///
/// Vorgabe: „Die Position bleibt dann erstmal leer und der neue Spieler kommt
/// auf die Bank." Der alte Weg nahm bei einer unvollständigen Elf die erste
/// besetzbare Formation — aus 4-4-2 ohne Verteidiger wurde 3-4-3, und ein
/// Stürmer rückte hinein, den niemand aufgestellt hatte.
void main() {
  const kader = RosterConfig();
  final alle = kader.validFormations();
  // Die Grundformation der Liga — der Maßstab bei Gleichstand.
  final basis = (kader.def, kader.mid, kader.fwd);

  test('eine vollständige Elf behält ihre Formation', () {
    expect(
      formationFuerElf(gesetzt: (4, 4, 2), besetzbar: alle, basis: basis),
      (4, 4, 2),
    );
    expect(
      formationFuerElf(gesetzt: (3, 5, 2), besetzbar: alle, basis: basis),
      (3, 5, 2),
    );
  });

  test('fehlt ein Verteidiger, bleibt es bei 4-4-2', () {
    // **Der gemeldete Fall.** 3-4-2 sind zehn Feldspieler; die Formation mit
    // dem kleinsten Überschuss ist 4-4-2 — die Lücke bleibt in der Abwehr.
    expect(
      formationFuerElf(gesetzt: (3, 4, 2), besetzbar: alle, basis: basis),
      (4, 4, 2),
    );
  });

  test('fehlt ein Stürmer, bleibt es bei 4-4-2', () {
    expect(
      formationFuerElf(gesetzt: (4, 4, 1), besetzbar: alle, basis: basis),
      (4, 4, 2),
    );
  });

  test('fehlt ein Mittelfeldspieler, bleibt es bei 4-4-2', () {
    expect(
      formationFuerElf(gesetzt: (4, 3, 2), besetzbar: alle, basis: basis),
      (4, 4, 2),
    );
  });

  test('kein gesetzter Spieler fällt heraus', () {
    // Die eigentliche Zusage: Was steht, bleibt stehen.
    for (final gesetzt in [
      (3, 4, 2),
      (4, 3, 2),
      (4, 4, 1),
      (5, 3, 1),
      (3, 5, 1),
    ]) {
      final f = formationFuerElf(
        gesetzt: gesetzt,
        besetzbar: alle,
        basis: basis,
      );
      expect(f, isNotNull, reason: '$gesetzt');
      expect(f!.$1, greaterThanOrEqualTo(gesetzt.$1), reason: '$gesetzt');
      expect(f.$2, greaterThanOrEqualTo(gesetzt.$2), reason: '$gesetzt');
      expect(f.$3, greaterThanOrEqualTo(gesetzt.$3), reason: '$gesetzt');
    }
  });

  test('zwei Lücken bleiben zwei Lücken', () {
    final f = formationFuerElf(
      gesetzt: (3, 4, 1),
      besetzbar: alle,
      basis: basis,
    )!;
    final ueberschuss = (f.$1 - 3) + (f.$2 - 4) + (f.$3 - 1);
    expect(ueberschuss, 2);
  });

  test('was der Kader nicht füllen kann, wird nicht vorgeschlagen', () {
    // `besetzbar` ist schon auf das gefiltert, was der Kader hergibt. Bleibt
    // nichts übrig, gibt es auch keine Formation.
    expect(
      formationFuerElf(gesetzt: (3, 4, 2), besetzbar: const [], basis: basis),
      isNull,
    );
  });

  test('eine Elf mit zu vielen auf einer Position findet nichts', () {
    // Sechs Verteidiger passen in keine gültige Formation — dann ist `null`
    // die ehrliche Antwort, nicht eine Formation, die jemanden hinauswirft.
    expect(
      formationFuerElf(gesetzt: (6, 4, 2), besetzbar: alle, basis: basis),
      isNull,
    );
  });
}
