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
import '../../../core/logic/vereins_kuerzel.dart';

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
    if (vereinKanonisch(f.home.name) == vereinKanonisch(verein)) {
      return NaechstesSpiel(
          gegner: f.away.name, anpfiff: f.kickoff.toLocal(), heim: true);
    }
    if (vereinKanonisch(f.away.name) == vereinKanonisch(verein)) {
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

/// **Alle Partien eines Vereins aus dem Spielplan.**
///
/// Gemeldet: *„Warum liegt für Schalke 04 kein Spielplan vor? Vorhin hatte ich
/// das auch bei Köln. Im Live-Tab sind die Spielpläne von Köln und Schalke ja
/// da — die fehlen nur im Spielerprofil."*
///
/// Genau diese beiden, und das ist kein Zufall: Der Spielplan-Reiter im Profil
/// verglich den Vereinsnamen **buchstabengenau** (`f.home.name == club`).
/// `players.club` trägt die OpenLigaDB-Schreibweise, der Spielplan die von
/// Sportmonks, und sie gehen bei **sieben von achtzehn** Vereinen auseinander:
///
/// | `players.club` | Spielplan |
/// |---|---|
/// | 1. FC Köln | FC Köln |
/// | FC Schalke 04 | Schalke 04 |
/// | 1. FSV Mainz 05 | FSV Mainz 05 |
/// | SV Werder Bremen | Werder Bremen |
/// | 1. FC Union Berlin | FC Union Berlin |
/// | SV 07 Elversberg | Elversberg |
/// | SC Paderborn 07 | Paderborn |
///
/// Der Live-Tab war deshalb in Ordnung: Er liest denselben Spielplan von
/// beiden Seiten und muss nichts abgleichen. Verglichen wird ab hier über
/// [vereinKanonisch] — dieselbe Reparatur, die der Server in Migration 0108
/// und der Client schon an fünf anderen Stellen hinter sich hat.
///
/// Nach Anstoß sortiert; die Eingabeliste bleibt unangetastet.
List<Fixture> spieleDesVereins(List<Fixture> alle, String verein) {
  final gesucht = vereinKanonisch(verein);
  return [
    for (final f in alle)
      if (vereinKanonisch(f.home.name) == gesucht ||
          vereinKanonisch(f.away.name) == gesucht)
        f,
  ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
}
