import '../models/fantasy_models.dart';

/// Baut die Slots auf eine neue Formation um — **ohne die Elf auszutauschen**.
///
/// Gemeldet: *„Wenn die Aufstellung geändert wird, sollen dieselben elf
/// Spieler im Kader bleiben. Wenn dann aber eine Positionsgruppe verringert
/// wird, geht einer raus. Dafür ist dann in der Positionsgruppe, wo mehrere
/// Leute dazukommen, ein freies Feld."*
///
/// Vorher wurde bei jedem Formationswechsel neu **aufgefüllt**: Die
/// bestehende Auswahl kam zuerst dran, der Rest wurde mit den punktbesten
/// Bankspielern ergänzt. Wer von 4-4-2 auf 3-5-2 wechselte, hatte also
/// ungefragt einen anderen Mittelfeldspieler in der Elf — und der Wechsel war
/// nicht mehr rückgängig zu machen, ohne von Hand nachzuziehen. Der
/// Formationsknopf ist ein Knopf für die **Aufstellung**, nicht für den Kader.
///
/// Die Regel ist deshalb rein rechnerisch und kennt weder Punkte noch Bank:
///
/// * **Reihenfolge bleibt.** Wer wo steht, entscheidet der Nutzer; wird eine
///   Gruppe kleiner, geht der **letzte** der Reihe raus. Das ist vorhersagbar,
///   „der schwächste" wäre es nicht.
/// * **Leere Plätze fallen zuerst weg.** `[A, null, B, C]` auf drei gekürzt
///   ergibt `[A, B, C]` — nicht `[A, null, B]`. Sonst verlöre man einen
///   Spieler an eine Lücke, die man gar nicht besetzt hatte.
/// * **Neue Plätze bleiben leer.** Genau darum ging es: Die Lücke ist die
///   Einladung, den herausgefallenen Spieler dort wieder hineinzusetzen.
///
/// Da die Elf immer elf Plätze hat, ist die Zahl der herausgefallenen Spieler
/// stets gleich der Zahl der neuen Lücken.
Map<PlayerPosition, List<String?>> umbauAufFormation({
  required Map<PlayerPosition, List<String?>> slots,
  required (int def, int mid, int fwd) formation,
  required int torhueter,
}) {
  final ziel = {
    PlayerPosition.gk: torhueter,
    PlayerPosition.def: formation.$1,
    PlayerPosition.mid: formation.$2,
    PlayerPosition.fwd: formation.$3,
  };
  final neu = <PlayerPosition, List<String?>>{};
  ziel.forEach((pos, anzahl) {
    final besetzt = [
      for (final id in slots[pos] ?? const <String?>[]) ?id,
    ];
    final bleiben = besetzt.take(anzahl).toList();
    neu[pos] = [
      for (var i = 0; i < anzahl; i++) i < bleiben.length ? bleiben[i] : null,
    ];
  });
  return neu;
}

/// Wer beim Umbau auf [formation] aus der Elf fällt (Reihenfolge wie im Feld).
///
/// Getrennt von [umbauAufFormation], damit die Oberfläche es sagen kann,
/// **bevor** jemand sich wundert, wo sein Spieler geblieben ist.
List<String> faelltRaus({
  required Map<PlayerPosition, List<String?>> slots,
  required (int def, int mid, int fwd) formation,
  required int torhueter,
}) {
  final vorher = {
    for (final e in slots.entries)
      for (final id in e.value) ?id,
  };
  final nachher = umbauAufFormation(
    slots: slots,
    formation: formation,
    torhueter: torhueter,
  );
  final geblieben = {
    for (final e in nachher.entries)
      for (final id in e.value) ?id,
  };
  return [
    for (final id in vorher)
      if (!geblieben.contains(id)) id,
  ];
}
