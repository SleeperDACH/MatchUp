/// **Wann liegt ein Spieler auf dem Waiver?**
///
/// Die Regel, wie sie gilt:
///
/// * Ein Spieler geht **mit dem Anpfiff seines Vereins** auf den Waiver — nicht
///   mit dem ersten Anpfiff des Spieltags. Wer Sonntag spielt, ist bis Sonntag
///   direkt zu holen.
/// * Der Waiver läuft bis **Montag 15:00**. Dann werden die Anträge in
///   Prioritätsreihenfolge abgearbeitet.
/// * **Englische Woche** (Spiele am Dienstag *und* Mittwoch): Donnerstag 15:00.
/// * Zwischen Frist und nächstem Anpfiff gilt wieder „first come, first
///   served": Wer frei ist, wird direkt geholt.
///
/// Maßgeblich ist der Server (`fantasy_auf_dem_wire`, Migration 0107); das hier
/// ist die Oberfläche dazu. Beide müssen dieselbe Regel meinen, sonst zeigt die
/// App ein grünes Plus, das der Server dann ablehnt — genau der Fehler, der als
/// „man kann ihn aufnehmen, es passiert überhaupt nichts" gemeldet wurde.
///
/// Gerechnet wird in **Ortszeit**. „Montag 15 Uhr" ist eine Uhrzeit für
/// Menschen und darf im Winter nicht auf 16 Uhr rutschen; `DateTime` ohne `utc`
/// tut hier genau das Richtige, solange das Gerät in Deutschland steht — wie
/// der Server, der dafür ausdrücklich `Europe/Berlin` rechnet.
library;

import '../../../core/models/models.dart';

/// Der nächste [wochentag] um 15:00 **echt nach** [ab].
DateTime naechsteFrist(DateTime ab, int wochentag) {
  var d = DateTime(ab.year, ab.month, ab.day, 15);
  while (d.weekday != wochentag || !d.isAfter(ab)) {
    d = DateTime(d.year, d.month, d.day + 1, 15);
  }
  return d;
}

/// Wann endet der Waiver dieser Runde? `null`, wenn die Runde keine Spiele hat.
///
/// Maßgeblich ist der **letzte** Anpfiff der Runde, nicht der erste: Der Waiver
/// soll erst schließen, wenn alle gespielt haben.
DateTime? waiverFrist(List<Fixture> spiele, int runde) {
  DateTime? letzter;
  var di = false, mi = false;
  for (final f in spiele) {
    if (f.round != runde) continue;
    final k = f.kickoff.toLocal();
    if (letzter == null || k.isAfter(letzter)) letzter = k;
    if (k.weekday == DateTime.tuesday) di = true;
    if (k.weekday == DateTime.wednesday) mi = true;
  }
  if (letzter == null) return null;
  return naechsteFrist(letzter, di && mi ? DateTime.thursday : DateTime.monday);
}

/// Die Runde, deren Waiver gerade offen ist — erster Anpfiff vorbei, Frist noch
/// nicht erreicht. `null` heißt: freie Phase.
int? wireRunde(List<Fixture> spiele, DateTime jetzt) {
  final runden = <int>{for (final f in spiele) f.round};
  int? offen;
  for (final r in runden) {
    DateTime? erster;
    for (final f in spiele) {
      if (f.round != r) continue;
      final k = f.kickoff.toLocal();
      if (erster == null || k.isBefore(erster)) erster = k;
    }
    if (erster == null || erster.isAfter(jetzt)) continue;
    final frist = waiverFrist(spiele, r);
    if (frist == null || !frist.isAfter(jetzt)) continue;
    if (offen == null || r > offen) offen = r;
  }
  return offen;
}

/// Liegt dieser Verein gerade auf dem Waiver?
///
/// **Kein Spiel gefunden heißt frei.** Der Pool enthält Spieler von Vereinen,
/// die an dem Spieltag nicht spielen oder gar nicht in der Liga sind — sie
/// festzuhalten brächte niemandem etwas.
bool vereinAufWire(String verein, List<Fixture> spiele, DateTime jetzt) {
  final runde = wireRunde(spiele, jetzt);
  if (runde == null) return false;
  for (final f in spiele) {
    if (f.round != runde) continue;
    if (f.home.name != verein && f.away.name != verein) continue;
    if (!f.kickoff.toLocal().isAfter(jetzt)) return true;
  }
  return false;
}

/// „Mo, 15:00" — die Frist so, wie sie in einer Zeile steht.
String fristKurz(DateTime frist) {
  const tage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final h = frist.hour.toString().padLeft(2, '0');
  final m = frist.minute.toString().padLeft(2, '0');
  return '${tage[frist.weekday - 1]}, $h:$m';
}
