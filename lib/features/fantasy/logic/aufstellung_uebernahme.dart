/// **Womit ein neuer Spieltag anfängt: mit der Elf der Vorwoche.**
///
/// Ohne das begänne jeder Spieltag bei null — wer nicht in die App schaut, hat
/// keine Elf und damit keine Punkte. Nachgezählt beim Einbau: zwölf
/// Aufstellungen für Spieltag 1, **eine** für Spieltag 2.
///
/// Maßgeblich ist der Server (`fantasy_aufstellung_uebernehmen`, Migration
/// 0110), der die Übernahme wirklich speichert. Das hier ist die Saat für den
/// Schirm in der Zeit dazwischen — beide müssen dieselbe Regel meinen, sonst
/// springt die Aufstellung unter der Hand um, sobald der Lauf durch ist.
library;

import '../models/fantasy_models.dart';

/// Die Elf, mit der der Schirm für [runde] startet — `null`, wenn es nichts zu
/// übernehmen gibt (dann schlägt der Schirm die beste Elf vor).
///
/// Genommen wird die **jüngste** Aufstellung vor [runde], nicht stur die der
/// Vorrunde: Wer einen Spieltag ausgesetzt hat, fiele sonst für immer aus der
/// Übernahme heraus.
///
/// Gefiltert wird auf [kader]. Ein Spieler, der inzwischen weg ist (Trade,
/// Waiver, Drop), hinterlässt einen leeren Platz — besser als eine Elf, die der
/// Server beim nächsten Speichern ablehnt.
Set<String>? uebernommeneElf(
  Iterable<FantasyLineup> meine,
  int runde,
  Set<String> kader,
) {
  final diese = meine.where((l) => l.round == runde && l.playerIds.isNotEmpty);
  if (diese.isNotEmpty) return _gefiltert(diese.first.playerIds, kader);

  final frueher = meine
      .where((l) => l.round < runde && l.playerIds.isNotEmpty)
      .toList()
    ..sort((a, b) => b.round.compareTo(a.round));
  if (frueher.isEmpty) return null;
  final elf = _gefiltert(frueher.first.playerIds, kader);
  return elf.isEmpty ? null : elf;
}

Set<String> _gefiltert(Iterable<String> ids, Set<String> kader) =>
    {for (final id in ids) if (kader.contains(id)) id};
