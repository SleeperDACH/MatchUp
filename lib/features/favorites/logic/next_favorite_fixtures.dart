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
      if (f.status != FixtureStatus.finished && gesehen.add(f.id)) f
  ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  if (kommend.isEmpty) return const [];

  // Tag des nächsten Spiels — in lokaler Zeit, sonst rutscht ein Anstoß um
  // 20:30 in UTC auf den Folgetag und der Samstag zerfiele in zwei Tage.
  final erstes = kommend.first.kickoff.toLocal();
  final tag = DateTime(erstes.year, erstes.month, erstes.day);
  return [
    for (final f in kommend)
      if (_istAmTag(f, tag)) f
  ];
}

bool _istAmTag(TeamFixture f, DateTime tag) {
  final lt = f.kickoff.toLocal();
  return lt.year == tag.year && lt.month == tag.month && lt.day == tag.day;
}
