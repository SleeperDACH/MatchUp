import '../../../core/models/models.dart';

/// Ausgang eines Spiels aus Sicht einer Mannschaft.
enum FormErgebnis {
  sieg('S'),
  remis('U'),
  niederlage('N');

  const FormErgebnis(this.buchstabe);
  final String buchstabe;
}

/// Die Form einer Mannschaft: ihre letzten [anzahl] gewerteten Spiele **vor**
/// [vor], älteste zuerst — das jüngste steht damit rechts, wie in jeder
/// Formtabelle.
///
/// Gezählt wird nur, was ein Endergebnis hat (`hasResult`). Ein laufendes
/// Spiel ist kein Ergebnis, und ein Spiel nach dem getippten gehört nicht zur
/// Form, mit der die Mannschaft hineingeht — sonst änderte sich die Anzeige
/// eines alten Spieltags rückwirkend.
List<FormErgebnis> formVor(
  Iterable<Fixture> spiele,
  String teamId,
  DateTime vor, {
  int anzahl = 5,
}) {
  final gespielt = spiele
      .where((f) =>
          f.hasResult &&
          f.kickoff.isBefore(vor) &&
          (f.home.id == teamId || f.away.id == teamId))
      .toList()
    ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  final letzte = gespielt.length > anzahl
      ? gespielt.sublist(gespielt.length - anzahl)
      : gespielt;
  return [
    for (final f in letzte)
      _ausgang(
        f.home.id == teamId ? f.homeScore! : f.awayScore!,
        f.home.id == teamId ? f.awayScore! : f.homeScore!,
      ),
  ];
}

FormErgebnis _ausgang(int eigene, int gegner) => eigene > gegner
    ? FormErgebnis.sieg
    : eigene == gegner
        ? FormErgebnis.remis
        : FormErgebnis.niederlage;

/// Aus welchen Spielplänen die Form gelesen wird.
///
/// **Im Pokal zählt die Liga-Form.** Der Pokal-Spielplan kennt je Verein ein
/// oder zwei Spiele, oft aus dem Vorjahr — „S" aus Runde 1 sagt über die Form
/// nichts. Für ein Pokalspiel werden deshalb die Ligen gefragt, in denen der
/// Verein spielt; maßgeblich ist die erste, die ihn kennt.
List<String> formQuellen(String leagueId) =>
    leagueId == Leagues.dfbPokal.id
        ? [Leagues.bundesliga.id, Leagues.bundesliga2.id, Leagues.liga3.id]
        : [leagueId];
