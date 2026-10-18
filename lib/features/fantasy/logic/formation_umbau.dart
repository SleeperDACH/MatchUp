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
  Set<String> gesperrt = const {},
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
    // **Gesperrte bleiben** (17.10.2026: Formation auch während des
    // Spieltags). Wird eine Gruppe kleiner, fallen zuerst die hinteren
    // **ungesperrten** Spieler heraus; wer schon gespielt hat, ist in der
    // Aufstellung verankert. Ohne Sperre bleibt es bei „der letzte der Reihe
    // geht".
    final bleiben = [...besetzt];
    for (var i = bleiben.length - 1;
        i >= 0 && bleiben.length > anzahl;
        i--) {
      if (!gesperrt.contains(bleiben[i])) bleiben.removeAt(i);
    }
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
  Set<String> gesperrt = const {},
}) {
  final vorher = {
    for (final e in slots.entries)
      for (final id in e.value) ?id,
  };
  final nachher = umbauAufFormation(
    slots: slots,
    formation: formation,
    torhueter: torhueter,
    gesperrt: gesperrt,
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

/// **Geht diese Formation, obwohl Spieler schon gespielt haben?**
///
/// `null`, wenn ja — sonst der Grund („3 Verteidiger stehen fest"). Eine
/// Formation geht nicht, sobald auf einer Position mehr **gesperrte** Spieler
/// stehen (Spiel angepfiffen), als sie dort Plätze hat: Sie müssten aus der
/// Elf, und das lässt der Server nicht zu (`fantasy_set_lineup`, 0084).
String? formationGesperrtWeil({
  required Map<PlayerPosition, List<String?>> slots,
  required (int def, int mid, int fwd) formation,
  required Set<String> gesperrt,
}) {
  if (gesperrt.isEmpty) return null;
  final plaetze = {
    PlayerPosition.def: formation.$1,
    PlayerPosition.mid: formation.$2,
    PlayerPosition.fwd: formation.$3,
  };
  // Einzahl und Mehrzahl sind im Deutschen hier gleich.
  const wort = {
    PlayerPosition.def: 'Verteidiger',
    PlayerPosition.mid: 'Mittelfeldspieler',
    PlayerPosition.fwd: 'Stürmer',
  };
  for (final MapEntry(key: pos, value: n) in plaetze.entries) {
    final fest = [
      for (final id in slots[pos] ?? const <String?>[])
        if (id != null && gesperrt.contains(id)) id,
    ].length;
    if (fest > n) {
      return '$fest ${wort[pos]} ${fest == 1 ? 'steht' : 'stehen'} schon fest';
    }
  }
  return null;
}
