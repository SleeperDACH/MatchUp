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

/// Stellt das Spiel des **obersten Favoriten** an den Anfang der Tagesliste.
///
/// [naechsteFavoritenSpiele] sortiert nach Anstoß — die richtige Ordnung für
/// eine Liste, die den Tag abbildet. Die Kopfkarte des Homescreens stellt aber
/// eine andere Frage: Von vier Vereinen, die an einem Samstag spielen, gehört
/// **meiner** nach oben, nicht der, der zufällig um 13:30 anfängt. „Meiner"
/// ist dabei der, der in der Favoritenreihenfolge oben steht
/// (`favoritenRaenge`) — dieselbe Reihenfolge, die der Favoriten-Tab zeigt.
///
/// Der Rest bleibt nach Anstoß sortiert: Wer die Liste darunter liest, liest
/// den Tagesverlauf. Nur ein Eintrag wird herausgehoben, nicht die Ordnung
/// umgeworfen.
///
/// [rang] liefert die Position des Vereins (kleiner ist weiter oben) oder
/// `null` für „gehört zu keinem Favoriten" — das kommt vor, wenn ein Spiel
/// über den Gegner in die Liste geraten ist.
List<TeamFixture> favoritenSpielZuerst({
  required List<TeamFixture> spiele,
  required int? Function(TeamFixture) rang,
}) {
  if (spiele.length < 2) return spiele;
  var besterIndex = 0;
  int? bester;
  for (var i = 0; i < spiele.length; i++) {
    final r = rang(spiele[i]);
    if (r == null) continue;
    // Bei Gleichstand gewinnt der frühere Anstoß — die Liste ist danach
    // sortiert, also genügt das strikte Kleiner.
    if (bester == null || r < bester) {
      bester = r;
      besterIndex = i;
    }
  }
  if (besterIndex == 0) return spiele;
  return [
    spiele[besterIndex],
    for (var i = 0; i < spiele.length; i++)
      if (i != besterIndex) spiele[i],
  ];
}
