import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/formation_umbau.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Ein Formationswechsel tauscht die Elf nicht aus.**
///
/// Gewünscht: *„Wenn die Aufstellung geändert wird, sollen dieselben elf
/// Spieler im Kader bleiben. Wenn dann aber eine Positionsgruppe verringert
/// wird, geht einer raus. Dafür ist dann in der Positionsgruppe, wo mehrere
/// Leute dazukommen, ein freies Feld."*
///
/// Vorher füllte der Wechsel die neue Formation mit den **punktbesten
/// Bankspielern** auf. Von 4-4-2 auf 3-5-2 hieß: ein Verteidiger raus (das ist
/// richtig) **und** ein fremder Mittelfeldspieler rein (das nicht). Der
/// Formationsknopf war damit ein Knopf für den Kader.

Map<PlayerPosition, List<String?>> _slots({
  List<String?> gk = const ['gk1'],
  List<String?> def = const ['d1', 'd2', 'd3', 'd4'],
  List<String?> mid = const ['m1', 'm2', 'm3', 'm4'],
  List<String?> fwd = const ['f1', 'f2'],
}) => {
      PlayerPosition.gk: gk,
      PlayerPosition.def: def,
      PlayerPosition.mid: mid,
      PlayerPosition.fwd: fwd,
    };

void main() {
  test('4-4-2 → 3-5-2: ein Verteidiger raus, ein Feld im Mittelfeld frei', () {
    final neu = umbauAufFormation(
      slots: _slots(),
      formation: (3, 5, 2),
      torhueter: 1,
    );

    expect(neu[PlayerPosition.def], ['d1', 'd2', 'd3'],
        reason: 'der letzte der Reihe geht raus');
    expect(neu[PlayerPosition.mid], ['m1', 'm2', 'm3', 'm4', null],
        reason: 'das neue Feld bleibt leer — niemand rückt ungefragt nach');
    expect(neu[PlayerPosition.fwd], ['f1', 'f2']);
    expect(neu[PlayerPosition.gk], ['gk1']);
  });

  test('so viele fallen raus, wie Felder frei werden', () {
    for (final fm in [(3, 5, 2), (5, 3, 2), (4, 3, 3), (3, 4, 3), (5, 2, 3)]) {
      final neu = umbauAufFormation(
        slots: _slots(),
        formation: fm,
        torhueter: 1,
      );
      final raus = faelltRaus(
        slots: _slots(),
        formation: fm,
        torhueter: 1,
      );
      final leer = [
        for (final liste in neu.values)
          for (final id in liste)
            if (id == null) id,
      ].length;
      expect(raus, hasLength(leer), reason: 'bei $fm');
      // Und die Elf bleibt eine Elf.
      expect(neu.values.fold(0, (n, l) => n + l.length), 11, reason: 'bei $fm');
    }
  });

  test('niemand fällt raus, wenn keine Gruppe kleiner wird', () {
    final neu = umbauAufFormation(
      slots: _slots(def: ['d1', 'd2', 'd3'], mid: ['m1', 'm2', 'm3', 'm4']),
      formation: (4, 4, 2),
      torhueter: 1,
    );
    // Die drei Verteidiger bleiben, der vierte Platz ist frei.
    expect(neu[PlayerPosition.def], ['d1', 'd2', 'd3', null]);
    expect(
      faelltRaus(
        slots: _slots(def: ['d1', 'd2', 'd3'], mid: ['m1', 'm2', 'm3', 'm4']),
        formation: (4, 4, 2),
        torhueter: 1,
      ),
      isEmpty,
    );
  });

  test('leere Plätze fallen vor den Spielern weg', () {
    // [d1, null, d2, d3] auf drei: d1, d2, d3 bleiben — nicht d1, null, d2.
    final neu = umbauAufFormation(
      slots: _slots(def: ['d1', null, 'd2', 'd3']),
      formation: (3, 5, 2),
      torhueter: 1,
    );
    expect(neu[PlayerPosition.def], ['d1', 'd2', 'd3']);
    expect(
      faelltRaus(
        slots: _slots(def: ['d1', null, 'd2', 'd3']),
        formation: (3, 5, 2),
        torhueter: 1,
      ),
      isEmpty,
      reason: 'die Lücke war schon da, es geht niemand verloren',
    );
  });

  test('hin und zurück bringt niemanden ungefragt herein', () {
    final hin = umbauAufFormation(
      slots: _slots(),
      formation: (3, 5, 2),
      torhueter: 1,
    );
    final zurueck = umbauAufFormation(
      slots: hin,
      formation: (4, 4, 2),
      torhueter: 1,
    );
    // d4 ist draußen und bleibt draußen; die Abwehr hat jetzt ein freies Feld.
    expect(zurueck[PlayerPosition.def], ['d1', 'd2', 'd3', null]);
    expect(zurueck[PlayerPosition.mid], ['m1', 'm2', 'm3', 'm4']);
  });
}
