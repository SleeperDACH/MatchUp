import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/wechsel_mit_formation.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// Bankspieler auf den Platz einer anderen Positionsgruppe — die Formation
/// passt sich an (20.10.2026).
void main() {
  const gk = PlayerPosition.gk;
  const def = PlayerPosition.def;
  const mid = PlayerPosition.mid;
  const fwd = PlayerPosition.fwd;
  const roster = RosterConfig.standard;

  // 4-4-2
  Map<PlayerPosition, List<String?>> elf() => {
        gk: ['t'],
        def: ['d1', 'd2', 'd3', 'd4'],
        mid: ['m1', 'm2', 'm3', 'm4'],
        fwd: ['s1', 's2'],
      };

  test('Mittelfeldspieler auf Abwehrplatz: aus 4-4-2 wird 3-5-2', () {
    final w = wechselMitFormation(
      slots: elf(),
      spielerId: 'mBank',
      spielerPos: mid,
      von: null,
      zielPos: def,
      zielIndex: 1,
      roster: roster,
    );
    expect(w.fehler, isNull);
    expect(w.slots[def], ['d1', 'd3', 'd4']);
    expect(w.slots[mid], ['m1', 'm2', 'm3', 'm4', 'mBank']);
    expect(w.slots[fwd], ['s1', 's2']);
    // Der Verdrängte ist nicht mehr in der Elf, sonst niemand.
    final drin = w.slots.values.expand((l) => l).toSet();
    expect(drin.contains('d2'), isFalse);
    expect(drin.length, 11);
  });

  test('Stürmer auf Mittelfeldplatz: aus 4-4-2 wird 4-3-3', () {
    final w = wechselMitFormation(
      slots: elf(),
      spielerId: 'sBank',
      spielerPos: fwd,
      von: null,
      zielPos: mid,
      zielIndex: 0,
      roster: roster,
    );
    expect(w.fehler, isNull);
    expect(w.slots[mid], ['m2', 'm3', 'm4']);
    expect(w.slots[fwd], ['s1', 's2', 'sBank']);
  });

  test('nicht erlaubte Formation: nichts ändert sich, Meldung nennt sie', () {
    // 3-5-2 → Mittelfeldspieler auf Abwehrplatz wäre 2-6-2.
    final start = {
      gk: <String?>['t'],
      def: <String?>['d1', 'd2', 'd3'],
      mid: <String?>['m1', 'm2', 'm3', 'm4', 'm5'],
      fwd: <String?>['s1', 's2'],
    };
    final w = wechselMitFormation(
      slots: start,
      spielerId: 'mBank',
      spielerPos: mid,
      von: null,
      zielPos: def,
      zielIndex: 0,
      roster: roster,
    );
    expect(w.fehler, contains('2-6-2'));
    expect(identical(w.slots, start), isTrue);
  });

  test('Torwart und Feld-zu-Feld gehen nicht', () {
    expect(
      wechselMitFormation(
        slots: elf(),
        spielerId: 'tBank',
        spielerPos: gk,
        von: null,
        zielPos: def,
        zielIndex: 0,
        roster: roster,
      ).fehler,
      isNotNull,
    );
    expect(
      wechselMitFormation(
        slots: elf(),
        spielerId: 'm1',
        spielerPos: mid,
        von: (mid, 0),
        zielPos: def,
        zielIndex: 0,
        roster: roster,
      ).fehler,
      isNotNull,
    );
  });

  test('ein leerer Platz der Zielgruppe fällt weg', () {
    final start = elf()..[def] = ['d1', null, 'd3', 'd4'];
    final w = wechselMitFormation(
      slots: start,
      spielerId: 'mBank',
      spielerPos: mid,
      von: null,
      zielPos: def,
      zielIndex: 1,
      roster: roster,
    );
    expect(w.fehler, isNull);
    expect(w.slots[def], ['d1', 'd3', 'd4']);
    expect(w.slots[mid]!.length, 5);
  });
}
