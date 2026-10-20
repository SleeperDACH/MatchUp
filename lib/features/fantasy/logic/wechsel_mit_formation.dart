import '../models/fantasy_models.dart';

/// **Ein Bankspieler auf den Platz einer anderen Positionsgruppe**
/// (20.10.2026, auf Ansage: „wenn man einen Spieler gegen eine andere
/// Positionsgruppe tauscht, wird die Formation automatisch mit angepasst").
///
/// Zieht man einen Mittelfeldspieler von der Bank auf einen Abwehrplatz, geht
/// der Verteidiger auf die Bank, die Abwehr wird um einen Platz kleiner und
/// das Mittelfeld um einen größer: aus 4-4-2 wird 3-5-2. Die übrigen zehn
/// bleiben, wo sie stehen — dieselbe Zusage wie beim Formationswechsel
/// (`umbauAufFormation`): Die App tauscht nie ungefragt jemanden aus.
///
/// Drei Fälle gehen nicht, und dann bleibt alles, wie es war ([fehler]):
///
/// * **Der Torwart tauscht nur mit einem Torwart.** Seine Zahl steht fest.
/// * **Vom Feld auf eine andere Gruppe** — beide stehen schon in der Elf; es
///   gäbe nichts zu tauschen, nur einen Platz weniger.
/// * **Die neue Formation ist nicht erlaubt** (Spannen der Liga, vier Stürmer
///   nur mit vier Verteidigern). Die Meldung nennt sie.
({Map<PlayerPosition, List<String?>> slots, String? fehler})
    wechselMitFormation({
  required Map<PlayerPosition, List<String?>> slots,
  required String spielerId,
  required PlayerPosition spielerPos,
  required (PlayerPosition, int)? von,
  required PlayerPosition zielPos,
  required int zielIndex,
  required RosterConfig roster,
  bool torwartImKader = true,
}) {
  ({Map<PlayerPosition, List<String?>> slots, String? fehler}) nein(
          String f) =>
      (slots: slots, fehler: f);

  if (spielerPos == zielPos) {
    return nein('Gleiche Position — das ist ein gewöhnlicher Tausch.');
  }
  if (spielerPos == PlayerPosition.gk || zielPos == PlayerPosition.gk) {
    return nein('Der Torwart lässt sich nur gegen einen Torwart tauschen.');
  }
  if (von != null) {
    return nein('Beide stehen schon in der Elf.');
  }

  final neu = {for (final e in slots.entries) e.key: [...e.value]};
  final ziel = neu[zielPos];
  if (ziel == null || zielIndex < 0 || zielIndex >= ziel.length) {
    return nein('Diesen Platz gibt es nicht.');
  }
  ziel.removeAt(zielIndex);
  (neu[spielerPos] ??= []).add(spielerId);

  int zahl(PlayerPosition p) => neu[p]?.length ?? 0;
  final ok = roster.isValidFormation(
    gkCount: zahl(PlayerPosition.gk),
    defCount: zahl(PlayerPosition.def),
    midCount: zahl(PlayerPosition.mid),
    fwdCount: zahl(PlayerPosition.fwd),
    torwartImKader: torwartImKader,
  );
  if (!ok) {
    final label = roster.formationLabel(
      defCount: zahl(PlayerPosition.def),
      midCount: zahl(PlayerPosition.mid),
      fwdCount: zahl(PlayerPosition.fwd),
    );
    return nein('$label ist in dieser Liga keine erlaubte Formation.');
  }
  return (slots: neu, fehler: null);
}
