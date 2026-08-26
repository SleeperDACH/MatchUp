import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';

/// Die nächsten Spiele der favorisierten Vereine: das früheste noch nicht
/// beendete — und **alle weiteren am selben Kalendertag**. Ein Fußball-
/// Samstag mit vier Vereinen soll auf dem Homescreen vollständig stehen,
/// nicht nur mit dem ersten Anstoß.
///
/// Erwartet die zusammengeführten Spielpläne der Favoriten (ein Eintrag kann
/// doppelt vorkommen, wenn zwei Favoriten gegeneinander spielen).
///
/// Pur gehalten (keine Provider, kein Netz), damit die Auswahlregel testbar
/// bleibt — sie hat mehr Kanten, als sie aussieht: Tagesgrenze in lokaler
/// Zeit, Doppelzählung bei Favorit gegen Favorit, laufende Spiele.
List<TeamFixture> naechsteFavoritenSpiele({
  required List<TeamFixture> fixtures,
  required DateTime jetzt,
}) {
  final gesehen = <String>{};
  final kommend = <TeamFixture>[
    for (final f in fixtures)
      // Wie im Favoriten-Tab: „noch nicht beendet" statt „Anstoß in der
      // Zukunft" — ein laufendes Spiel ist das nächste, nicht ein vergangenes.
      if (f.status != FixtureStatus.finished && gesehen.add(f.id)) f,
  ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  if (kommend.isEmpty) return const [];

  // Tag des nächsten Spiels — in lokaler Zeit, sonst rutscht ein Anstoß um
  // 20:30 in UTC auf den Folgetag und der Samstag zerfiele in zwei Tage.
  final erstes = kommend.first.kickoff.toLocal();
  final tag = DateTime(erstes.year, erstes.month, erstes.day);
  return [
    for (final f in kommend)
      if (_istAmTag(f, tag)) f,
  ];
}

bool _istAmTag(TeamFixture f, DateTime tag) {
  final lt = f.kickoff.toLocal();
  return lt.year == tag.year && lt.month == tag.month && lt.day == tag.day;
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
