/// **Was in der Punktebox steht, solange es keine Punkte gibt.**
///
/// Vorher stand dort ein Strich — und davor sogar eine 0, was schlimmer war:
/// „hat gespielt und nichts geholt" sah aus wie „war noch gar nicht dran".
/// Ein Strich sagt zwar nichts Falsches, aber auch nichts. Die Frage vor einem
/// Spieltag ist ohnehin eine andere: **wann spielt er, und gegen wen?**
///
/// Maßgeblich ist der **Anpfiff seines Vereins**, nicht ob schon Statistiken
/// da sind. Genau daran hing der gemeldete Fehler: Zum Start des Spieltags
/// standen bereits 0,0 Punkte, weil der Statistik-Datensatz früher da war als
/// der Anstoß.
library;

import '../../../core/models/models.dart';

class NaechstesSpiel {
  const NaechstesSpiel({
    required this.gegner,
    required this.anpfiff,
    required this.heim,
  });

  /// Vereinsname des Gegners (nicht das Kürzel — das macht die Anzeige).
  final String gegner;
  final DateTime anpfiff;

  /// Spielt der eigene Verein zu Hause?
  final bool heim;
}

/// Das Spiel dieses Vereins in [runde] — `null`, wenn er nicht angesetzt ist.
///
/// **Kein Spiel gefunden ist kein Fehler.** Ein Kader kann Spieler enthalten,
/// deren Verein an diesem Spieltag frei hat oder gar nicht in der Liga
/// spielt; für sie gibt es weder Punkte noch einen Anstoß.
NaechstesSpiel? naechstesSpiel(
  List<Fixture> spiele,
  int runde,
  String verein,
) {
  for (final f in spiele) {
    if (f.round != runde) continue;
    if (f.home.name == verein) {
      return NaechstesSpiel(
          gegner: f.away.name, anpfiff: f.kickoff.toLocal(), heim: true);
    }
    if (f.away.name == verein) {
      return NaechstesSpiel(
          gegner: f.home.name, anpfiff: f.kickoff.toLocal(), heim: false);
    }
  }
  return null;
}

/// „Sa 15:30" — Wochentag und Uhrzeit, wie sie in die Box passen.
String anpfiffKurz(DateTime anpfiff) {
  const tage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final h = anpfiff.hour.toString().padLeft(2, '0');
  final m = anpfiff.minute.toString().padLeft(2, '0');
  return '${tage[anpfiff.weekday - 1]} $h:$m';
}
