import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/formation_luecke.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Warum eine Formation nicht spielbar ist — und dass sie trotzdem dasteht.**
///
/// Gemeldet: „Es fehlen Aufstellungen. In den Patchnotes steht was von 8 auf
/// 11, aber ich sehe nur 7." Die Zahl in der Patchnote war falsch, die Sieben
/// aber richtig gezählt.
Map<PlayerPosition, int> _kader({int gk = 1, int def = 5, int mid = 4, int fwd = 6}) => {
      PlayerPosition.gk: gk,
      PlayerPosition.def: def,
      PlayerPosition.mid: mid,
      PlayerPosition.fwd: fwd,
    };

void main() {
  test('mit vollem Kader fehlt nichts', () {
    for (final f in const RosterConfig().validFormations()) {
      expect(formationLuecke(f, imKader: _kader(def: 5, mid: 5, fwd: 4)), isNull,
          reason: '${f.$1}-${f.$2}-${f.$3}');
    }
  });

  test('der gemeldete Kader kann genau sieben der neun Formationen', () {
    // **Der Fall aus der Meldung**, nachgerechnet: 1 TW, 5 ABW, 4 MF, 6 ST.
    // Die beiden Formationen mit fünf im Mittelfeld fallen aus — und wurden
    // vorher stillschweigend weggelassen, weshalb sieben statt neun dastanden.
    final alle = const RosterConfig().validFormations();
    expect(alle, hasLength(9));

    final spielbar = [
      for (final f in alle)
        if (formationLuecke(f, imKader: _kader()) == null) f,
    ];
    expect(spielbar, hasLength(7));

    final unvollstaendig = [
      for (final f in alle)
        if (formationLuecke(f, imKader: _kader()) != null)
          '${f.$1}-${f.$2}-${f.$3}',
    ];
    expect(unvollstaendig, ['3-5-2', '4-5-1']);
  });

  test('eine Lücke sperrt die Formation nicht', () {
    // **Die Bedeutung dieser Funktion hat sich geändert.** Sie sagt, *was*
    // fehlt — nicht, dass die Formation verboten wäre. Auf Ansage: „Wenn man
    // keine fünf Verteidiger hat, darf die fünfte Kette trotzdem nicht
    // ausgegraut sein. Da ist es dann halt leer … aber es soll auswählbar
    // sein."
    //
    // Der Text ist damit ein Hinweis nach dem Umstellen, kein Riegel davor.
    // Was die Oberfläche daraus macht, hält `aufstellung_luecke_test.dart`
    // fest; hier steht nur, dass der Text eine Lücke benennt und sonst nichts.
    final luecke = formationLuecke((5, 4, 1), imKader: _kader(def: 3));
    expect(luecke, '2 Abwehrspieler');
    expect(luecke, isNot(contains('nicht')));
  });

  test('die Lücke wird benannt, nicht nur festgestellt', () {
    expect(formationLuecke((3, 5, 2), imKader: _kader()),
        '1 Mittelfeldspieler');
    expect(formationLuecke((5, 4, 1), imKader: _kader(def: 3)),
        '2 Abwehrspieler');
  });

  test('mehrere Lücken werden zusammen genannt', () {
    expect(
      formationLuecke((5, 4, 2), imKader: _kader(def: 3, mid: 2, fwd: 6)),
      '2 Abwehrspieler und 2 Mittelfeldspieler',
    );
  });

  test('der Torwart zählt nicht als Formationslücke', () {
    // Ohne Torwart steht gar keine Elf — das ist kein Formationsproblem, und
    // ein Hinweis darauf am 4-4-2-Knopf wäre am Thema vorbei.
    expect(formationLuecke((4, 4, 2), imKader: _kader(gk: 0)), isNull);
  });
}
