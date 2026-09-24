import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/formation_umbau.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Eine Formation, für die der Kader nicht reicht, ist trotzdem wählbar.**
///
/// Auf Ansage: *„Wenn man keine fünf Verteidiger hat, darf die fünfte Kette
/// trotzdem nicht ausgegraut sein. Da ist es dann halt leer, und wenn man in
/// den Spieltag geht und man einen weniger aufgestellt hat, hat man Pech, aber
/// es soll auswählbar sein."*
///
/// Vorher wehrte der Knopf den Tipp ab und erklärte, was fehle. Das ist eine
/// Bevormundung: Mit welcher Elf jemand in den Spieltag geht, entscheidet er.
/// Der Umbau muss das aushalten — er darf keinen Spieler verlieren und keinen
/// Platz erfinden, sondern lässt die Lücke offen.
void main() {
  Map<PlayerPosition, List<String?>> vierViertZwei() => {
        PlayerPosition.gk: ['tw'],
        PlayerPosition.def: ['d1', 'd2', 'd3', 'd4'],
        PlayerPosition.mid: ['m1', 'm2', 'm3', 'm4'],
        PlayerPosition.fwd: ['f1', 'f2'],
      };

  test('Fünferkette ohne fünften Verteidiger lässt den Platz leer', () {
    final neu = umbauAufFormation(
      slots: vierViertZwei(),
      formation: (5, 3, 2),
      torhueter: 1,
    );

    // Fünf Plätze in der Abwehr, vier davon besetzt — der fünfte ist die
    // Lücke, die man füllen kann, aber nicht muss.
    expect(neu[PlayerPosition.def], hasLength(5));
    expect(neu[PlayerPosition.def], ['d1', 'd2', 'd3', 'd4', null]);

    // **Kein Spieler geht dabei verloren, der bleiben könnte.** Das Mittelfeld
    // schrumpft von vier auf drei; heraus fällt der letzte der Reihe, nicht
    // irgendeiner.
    expect(neu[PlayerPosition.mid], ['m1', 'm2', 'm3']);
    expect(neu[PlayerPosition.fwd], ['f1', 'f2']);
    expect(neu[PlayerPosition.gk], ['tw']);
  });

  test('auch mehrere Lücken auf einmal sind erlaubt', () {
    // 3-5-2 bei drei Mittelfeldspielern: zwei Plätze bleiben offen.
    final duenn = {
      PlayerPosition.gk: <String?>['tw'],
      PlayerPosition.def: <String?>['d1', 'd2', 'd3'],
      PlayerPosition.mid: <String?>['m1', 'm2', 'm3'],
      PlayerPosition.fwd: <String?>['f1', 'f2'],
    };

    final neu = umbauAufFormation(
      slots: duenn,
      formation: (3, 5, 2),
      torhueter: 1,
    );

    expect(neu[PlayerPosition.mid], ['m1', 'm2', 'm3', null, null]);
    expect(neu[PlayerPosition.def], ['d1', 'd2', 'd3']);
  });

  test('die Elf behält ihre elf Plätze, besetzt oder nicht', () {
    for (final fm in const [(5, 4, 1), (3, 5, 2), (4, 3, 3)]) {
      final neu = umbauAufFormation(
        slots: vierViertZwei(),
        formation: fm,
        torhueter: 1,
      );
      final plaetze = neu.values.fold<int>(0, (s, l) => s + l.length);
      expect(plaetze, 11, reason: '${fm.$1}-${fm.$2}-${fm.$3}');
    }
  });
}
