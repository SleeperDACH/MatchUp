/// **Warum eine Formation nicht spielbar ist.**
///
/// Gemeldet: *„Es fehlen Aufstellungen. In den Patchnotes steht was von 8 auf
/// 11, aber ich sehe nur 7."* Die Zahl in der Patchnote war falsch (es sind
/// neun), die Sieben aber richtig gezählt: Der Kader hatte vier
/// Mittelfeldspieler, und die beiden Formationen mit fünf im Mittelfeld
/// (3-5-2 und 4-5-1) wurden **stillschweigend weggelassen**.
///
/// Weglassen war der Fehler. „Geht nicht" ist ein anderer Zustand als „gibt es
/// nicht" — wer zählt, kommt sonst auf eine andere Zahl als die Regel und
/// hält das für einen Fehler. Dieselbe Lehre wie an einem halben Dutzend
/// anderer Stellen in dieser App.
library;

import '../models/fantasy_models.dart';

/// Was dem Kader für [formation] fehlt — `null`, wenn sie spielbar ist.
///
/// [imKader] zählt die Spieler je Position. Der Torwart bleibt außen vor: Ohne
/// ihn steht gar keine Elf, und das ist kein Formationsproblem.
String? formationLuecke(
  (int def, int mid, int fwd) formation, {
  required Map<PlayerPosition, int> imKader,
}) {
  int da(PlayerPosition p) => imKader[p] ?? 0;
  final luecken = <String>[
    if (formation.$1 > da(PlayerPosition.def))
      _wortform(formation.$1 - da(PlayerPosition.def), 'Abwehrspieler'),
    if (formation.$2 > da(PlayerPosition.mid))
      _wortform(formation.$2 - da(PlayerPosition.mid), 'Mittelfeldspieler'),
    if (formation.$3 > da(PlayerPosition.fwd))
      _wortform(formation.$3 - da(PlayerPosition.fwd), 'Stürmer'),
  ];
  return luecken.isEmpty ? null : luecken.join(' und ');
}

/// „1 Stürmer" bzw. „2 Stürmer" — die Lücke in Worten.
///
/// Die Positionsbezeichnungen sind im Deutschen im Plural unverändert, deshalb
/// unterscheidet sich nur die Zahl davor.
String _wortform(int zahl, String was) => '$zahl $was';
