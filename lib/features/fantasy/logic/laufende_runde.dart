/// Der laufende Spieltag im Spielerprofil: **ab Abpfiff seines Spiels**, nicht
/// erst nach dem ganzen Spieltag.
///
/// Gemeldet: „Im Spielerprofil wird die Punktzahl des aktuellen Spiels erst
/// nach dem Spieltag angezeigt. Das kann ruhig bei den jeweiligen Spielern
/// schon nach Abpfiff angezeigt werden."
///
/// Die Saisonstatistik (`seasonStatsProvider`) wird einmal je Sitzung geladen
/// und während eines Spieltags nicht aufgefrischt — eine Saison sind über
/// tausend Zeilen, die im 30-Sekunden-Takt nachzuladen wäre teuer. Die eine
/// Runde, um die es geht, liegt aber ohnehin frisch vor: `roundStatsProvider`
/// lädt sie während eines Spieltags alle 30 Sekunden nach. Diese Funktion
/// setzt beides zusammen.
///
/// Regeln für die laufende Runde:
///  * **Sein Spiel ist abgepfiffen** → seine Zeile aus den frischen Daten.
///    Hat er nicht gespielt, steht die Runde trotzdem als gewertet da (die
///    Zeile zeigt dann „–", nicht „noch offen").
///  * **Sein Verein hat frei** → die Runde zählt erst, wenn alle Spiele des
///    Spieltags abgepfiffen sind.
///  * **Sonst** fällt die Runde heraus, auch wenn die Saisonstatistik schon
///    einen Zwischenstand von ihr kennt: Ein halber Spieltag drückte sonst
///    den Schnitt, und eine Zahl vor dem Abpfiff wäre keine.
library;

import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/models/models.dart';
import 'fantasy_scoring_engine.dart';

Map<int, Map<String, PlayerMatchStats>> mitLaufenderRunde({
  required Map<int, Map<String, PlayerMatchStats>> saison,
  required int? runde,
  required String spielerId,
  required String verein,
  required List<Fixture> spiele,
  required Map<String, PlayerMatchStats>? live,
  DateTime? jetzt,
}) {
  if (runde == null) return saison;
  final uhr = jetzt ?? DateTime.now();
  // **Abgepfiffen nach Status oder nach der Uhr** (17.10.2026, gemeldet:
  // „bei den Spielern, die schon gespielt haben, steht noch nichts"). Der
  // Spielplan im Client wird nicht laufend gespiegelt; sein Status hing nach
  // dem Abpfiff noch auf „läuft". Zwei Stunden nach Anpfiff ist jedes Spiel
  // durch — dieselbe Annahme wie in `fantasy_trade_frei_ab`.
  bool durch(Fixture f) =>
      f.status == FixtureStatus.finished ||
      uhr.isAfter(f.kickoff.add(const Duration(hours: 2)));
  final dieser = [
    for (final f in spiele)
      if (f.round == runde) f,
  ];
  if (dieser.isEmpty) return saison;

  final meiner = vereinKanonisch(verein);
  final sein = dieser
      .where((f) =>
          vereinKanonisch(f.home.name) == meiner ||
          vereinKanonisch(f.away.name) == meiner)
      .firstOrNull;
  final fertig = sein != null ? durch(sein) : dieser.every(durch);

  final aus = {...saison}..remove(runde);
  if (!fertig) return aus;

  // Frische Daten zuerst, die Saisonstatistik als Rückfall, falls die
  // Runde gerade noch lädt.
  final quelle = live ?? saison[runde] ?? const <String, PlayerMatchStats>{};
  final seine = quelle[spielerId];
  aus[runde] = {spielerId: ?seine};
  return aus;
}
