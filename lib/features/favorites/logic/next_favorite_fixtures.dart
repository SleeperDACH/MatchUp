import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';

/// **Die Fußballwoche endet Montag um 15:00.**
///
/// Gewünscht: *„Statt einem Spiel an dem Tag den Bereich umbauen in ‚Mein
/// Wochenende' und alle Spiele meiner Favoriten von Freitag bis einschließlich
/// Montag anzeigen. Trotzdem werden die Spiele in der Box oben weiterhin
/// angezeigt, bis Montag. Auch da gilt: Montag, 15:00 Uhr."*
///
/// Es ist **derselbe Schnitt**, an dem in dieser App schon die Waiver-Anträge
/// vergeben werden und der Fantasy-Spieltag wechselt (siehe
/// `currentFantasyRound`). Ein Termin in der Woche, nicht drei.
///
/// Zurück kommt das Fenster [von, bis): Freitag 00:00 bis Montag 15:00.
/// Maßgeblich ist der **nächste** Montag 15:00 nach [jetzt] — daraus folgt
/// alles Übrige von selbst:
///
/// | [jetzt] | Fenster |
/// |---|---|
/// | Samstag | das laufende Wochenende |
/// | Montag 10:00 | immer noch das vergangene |
/// | Montag 16:00 | schon das kommende |
/// | Mittwoch | das kommende |
({DateTime von, DateTime bis}) fussballWoche(DateTime jetzt) {
  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  // `DateTime.monday` ist 1; bis zum nächsten Montag sind es (8 - weekday) % 7
  // Tage, und 0 bedeutet „heute ist Montag".
  final bisMontag = (DateTime.monday - jetzt.weekday + 7) % 7;
  var bis = heute.add(Duration(days: bisMontag)).add(const Duration(hours: 15));
  // Der Montag ist schon vorbei: dann gilt der übernächste.
  if (!bis.isAfter(jetzt)) bis = bis.add(const Duration(days: 7));
  final von = DateTime(bis.year, bis.month, bis.day).subtract(
    const Duration(days: 3),
  );
  return (von: von, bis: bis);
}

/// Alle Spiele der favorisierten Vereine in dieser Fußballwoche.
///
/// **Auch die gespielten.** Genau darum ging es: Bis zum Montag soll das
/// Wochenende stehen bleiben, mit Ergebnis. Vorher zeigte der Homescreen das
/// früheste **noch nicht beendete** Spiel und alles vom selben Kalendertag —
/// nach dem Abpfiff sprang er auf den nächsten Spieltag, und das gerade
/// gespielte Wochenende war weg.
///
/// Erwartet die zusammengeführten Spielpläne der Favoriten (ein Eintrag kann
/// doppelt vorkommen, wenn zwei Favoriten gegeneinander spielen).
///
/// **Was bewusst herausfällt:** Partien unter der Woche, also Dienstag und
/// Mittwoch. Der Abschnitt heißt „Mein Wochenende", und ein englisches Spiel
/// gehört nicht hinein; für den vollständigen Spielplan gibt es den
/// Favoriten-Tab.
///
/// Pur gehalten (keine Provider, kein Netz), damit die Regel prüfbar bleibt —
/// sie hat mehr Kanten, als sie aussieht: Fenstergrenze in lokaler Zeit,
/// Doppelzählung bei Favorit gegen Favorit, der Montag als Scharnier.
List<TeamFixture> wochenendSpiele({
  required List<TeamFixture> fixtures,
  required DateTime jetzt,
}) {
  final fenster = fussballWoche(jetzt);
  final gesehen = <String>{};
  final drin = <TeamFixture>[
    for (final f in fixtures)
      if (gesehen.add(f.id) && _imFenster(f, fenster.von, fenster.bis)) f,
  ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  return drin;
}

bool _imFenster(TeamFixture f, DateTime von, DateTime bis) {
  // Ortszeit, sonst rutscht ein Anstoß um 20:30 in UTC auf den Folgetag und
  // der Freitagabend fiele aus dem Fenster.
  final lt = f.kickoff.toLocal();
  return !lt.isBefore(von) && lt.isBefore(bis);
}

/// Stellt das Spiel an den Anfang, das die Kopfkarte tragen soll.
///
/// **Die Regel ist der nächste Anpfiff** (auf Ansage, 07.09.2026). Der
/// Favoritenrang entscheidet **nur bei gleicher Anstoßzeit** — an einem
/// Samstag um 15:30 mit drei eigenen Vereinen gehört meiner nach oben, sonst
/// zählt allein, was als Nächstes angepfiffen wird.
///
/// Vorher galt der Rang unbedingt („wer Bayern über Bochum stellt, will an
/// einem Samstag mit beiden Bayern oben sehen"). Das ist ausdrücklich
/// zurückgenommen: Es schob eine Partie nach oben, die erst Stunden später
/// beginnt, während eine andere schon läuft.
///
/// **Abgepfiffenes kommt nicht auf die Kopfkarte**, solange im Fenster noch
/// etwas aussteht. Ist alles gespielt — Sonntagabend bis Montag 15:00 —, bleibt
/// das **zuletzt** gespielte oben stehen: Es ist das, worüber man dann redet,
/// und eine leere Karte wäre schlechter.
///
/// Der Rest bleibt, wie er kam. Nur ein Eintrag wird herausgehoben, die
/// Ordnung wird nicht umgeworfen — der Abschnitt „Mein Wochenende" sortiert
/// ohnehin selbst nach Anstoß.
///
/// [rang] liefert die Position des Vereins (kleiner ist weiter oben) oder
/// `null` für „gehört zu keinem Favoriten" — das kommt vor, wenn ein Spiel
/// über den Gegner in die Liste geraten ist.
List<TeamFixture> favoritenSpielZuerst({
  required List<TeamFixture> spiele,
  required int? Function(TeamFixture) rang,
}) {
  if (spiele.length < 2) return spiele;

  final offen = [
    for (var i = 0; i < spiele.length; i++)
      if (spiele[i].status != FixtureStatus.finished) i,
  ];
  final alleGespielt = offen.isEmpty;
  final kandidaten = alleGespielt
      ? [for (var i = 0; i < spiele.length; i++) i]
      : offen;

  // Steht noch etwas aus, zählt der **früheste** Anpfiff; ist alles gespielt,
  // der **späteste**. Beides ist dasselbe „das aktuellste Spiel", einmal nach
  // vorn und einmal nach hinten gelesen.
  var besterIndex = kandidaten.first;
  for (final i in kandidaten) {
    final a = spiele[i].kickoff;
    final b = spiele[besterIndex].kickoff;
    if (a == b) {
      // Gleiche Anstoßzeit: jetzt erst entscheidet der Favoritenrang. Ein
      // unbekannter Verein (`null`) verliert gegen jeden bekannten.
      final ra = rang(spiele[i]);
      final rb = rang(spiele[besterIndex]);
      if (ra != null && (rb == null || ra < rb)) besterIndex = i;
      continue;
    }
    final besser = alleGespielt ? a.isAfter(b) : a.isBefore(b);
    if (besser) besterIndex = i;
  }

  if (besterIndex == 0) return spiele;
  return [
    spiele[besterIndex],
    for (var i = 0; i < spiele.length; i++)
      if (i != besterIndex) spiele[i],
  ];
}
