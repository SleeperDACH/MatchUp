/// **Welche Formation zu einer unvollständigen Elf gehört.**
///
/// Vorgabe: *„Man muss zwischen den Spieltagen Spieler droppen können, die in
/// der Startaufstellung stehen. Die Position bleibt dann erstmal leer und der
/// neue Spieler kommt auf die Bank."*
///
/// Genau daran scheiterte der Schirm beim **Wiederöffnen**. Solange er offen
/// blieb, stand die Lücke richtig: Die Slots bleiben stehen, der gedroppte
/// Platz wird leer. Beim nächsten Öffnen wird die Elf aber aus der
/// gespeicherten Liste neu aufgebaut — und zehn Spieler sind keine gültige
/// Formation. Der alte Weg nahm dann *irgendeine* passende (die erste
/// besetzbare) und schob damit stumm Spieler aus der Elf, die gar nicht
/// gemeint waren: aus 4-4-2 ohne einen Verteidiger wurde 3-4-3, und ein
/// Stürmer rückte hinein.
library;

import '../models/fantasy_models.dart';

/// Die Formation, in der [gesetzt] vollständig Platz hat — `null`, wenn keine
/// passt.
///
/// [besetzbar] sind die Formationen, die der Kader überhaupt füllen kann.
///
/// Gewählt wird die mit dem **kleinsten Überschuss**: Jeder gesetzte Spieler
/// bleibt stehen, und es entstehen genau so viele Lücken, wie Spieler fehlen.
///
/// Bei Gleichstand entscheidet die Nähe zur **Grundformation der Liga**
/// ([basis], aus `RosterConfig`). Ohne diesen Maßstab wäre die Wahl beliebig:
/// Fehlt aus 4-4-2 ein Verteidiger, sind 3-4-3, 3-5-2 und 4-4-2 alle „einen
/// Spieler entfernt" — und der Reihe nach genommen gewinnt 3-4-3, was einen
/// Stürmer in die Elf schöbe, den niemand aufgestellt hat. Die Grundformation
/// ist das Nächstbeste zu „wie es vorher aussah".
(int def, int mid, int fwd)? formationFuerElf({
  required (int def, int mid, int fwd) gesetzt,
  required List<(int def, int mid, int fwd)> besetzbar,
  (int def, int mid, int fwd) basis = const (4, 4, 2),
}) {
  (int, int, int)? beste;
  var besterUeberschuss = 1 << 30;
  var besteNaehe = 1 << 30;
  for (final f in besetzbar) {
    if (f.$1 < gesetzt.$1 || f.$2 < gesetzt.$2 || f.$3 < gesetzt.$3) continue;
    final ueberschuss =
        (f.$1 - gesetzt.$1) + (f.$2 - gesetzt.$2) + (f.$3 - gesetzt.$3);
    final naehe =
        (f.$1 - basis.$1).abs() +
        (f.$2 - basis.$2).abs() +
        (f.$3 - basis.$3).abs();
    if (ueberschuss < besterUeberschuss ||
        (ueberschuss == besterUeberschuss && naehe < besteNaehe)) {
      besterUeberschuss = ueberschuss;
      besteNaehe = naehe;
      beste = f;
    }
  }
  return beste;
}

/// Wie viele Spieler je Position in [ids] stehen.
(int def, int mid, int fwd) besetzungAus(
  Set<String> ids,
  Map<PlayerPosition, List<FantasyPlayer>> nachPosition,
) {
  int zahl(PlayerPosition p) => (nachPosition[p] ?? const <FantasyPlayer>[])
      .where((s) => ids.contains(s.id))
      .length;
  return (
    zahl(PlayerPosition.def),
    zahl(PlayerPosition.mid),
    zahl(PlayerPosition.fwd),
  );
}
