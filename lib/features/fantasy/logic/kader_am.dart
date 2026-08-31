/// **Der Kader, wie er zu einem Zeitpunkt aussah.**
///
/// Gemeldet: *„SFV03 hatte keine 230 Punkte auf der Bank."* Stimmt — der
/// Rückblick rechnete mit dem **heutigen** Kader. Wer nach dem Spieltag geholt
/// wurde, stand darin, und seine Punkte aus jenem Spieltag landeten auf der
/// Bank des neuen Besitzers. Wer abgegeben wurde, fehlte umgekehrt.
///
/// Ein Rückblick auf einen abgeschlossenen Spieltag muss den Stand von damals
/// benutzen. Die Bewegungen dafür stehen seit Migration 0096 mit Zeitstempel
/// in `fantasy_roster_moves` — dieselbe Quelle, aus der auch der
/// Transfers-Bereich lebt.
library;

import '../models/fantasy_models.dart';
import '../models/roster_move.dart';

/// Der Kader zum [stichtag], rekonstruiert aus dem heutigen Bestand und den
/// Bewegungen **danach**.
///
/// Rückwärts gerechnet: Ein Zugang nach dem Stichtag wird herausgenommen, ein
/// Abgang nach dem Stichtag wieder eingesetzt.
///
/// **Ohne Bewegungen bleibt es der heutige Kader.** Für einen laufenden
/// Spieltag ist das genau richtig; für einen alten ist es die beste Auskunft,
/// die es gibt, wenn das Protokoll (noch) nichts hergibt.
List<RosterEntry> kaderAm({
  required List<RosterEntry> aktuell,
  required List<RosterMove> bewegungen,
  required DateTime stichtag,
}) {
  // Schlüssel ist Manager **und** Spieler: Ein Trade ist für den einen ein
  // Abgang und für den anderen ein Zugang, beide zur selben Zeit.
  final stand = <String, RosterEntry>{
    for (final r in aktuell) '${r.managerId}|${r.playerId}': r,
  };

  for (final b in bewegungen) {
    if (!b.passiertAm.isAfter(stichtag)) continue;
    final schluessel = '${b.managerId}|${b.playerId}';
    if (b.zugang) {
      stand.remove(schluessel);
    } else {
      stand[schluessel] = RosterEntry(
        managerId: b.managerId,
        playerId: b.playerId,
        acquiredVia: b.weg ?? 'draft',
      );
    }
  }
  return stand.values.toList();
}

/// Wann ein Spieltag **abgepfiffen** war: letzter Anpfiff plus zwei Stunden
/// Spielzeit.
///
/// Dieselbe Annahme wie serverseitig in `fantasy_trade_frei_ab`. Eine echte
/// Abpfiffzeit liefert keine der beiden Quellen; zwei Stunden liegen bei jedem
/// Spiel auf der sicheren Seite.
DateTime? abpfiffDerRunde(Iterable<DateTime> anpfiffe) {
  DateTime? letzter;
  for (final a in anpfiffe) {
    if (letzter == null || a.isAfter(letzter)) letzter = a;
  }
  return letzter?.add(const Duration(hours: 2));
}
