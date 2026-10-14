import '../models/fantasy_models.dart';
import '../providers.dart' show gewerteteRunden;
import 'fantasy_scoring_engine.dart';

/// Was jede Head-to-Head-Ansicht braucht: die Reihenfolge der Manager (sie
/// bestimmt die Paarungen) und die Punkte je **gewertetem** Spieltag.
///
/// **Steht einmal da, weil sie an zwei Stellen gebraucht wird** — in der
/// Tabelle und im Saisonverlauf des Ligaprofils. Zwei Fassungen derselben
/// Rechnung sind in diesem Projekt jedes Mal auseinandergelaufen (die
/// Startelf-Summe, `formatPoints`, die Vereinsnamen); hier hieße das: Das
/// Profil zeigt eine Bilanz, die der Tabelle widerspricht.
typedef H2HGrundlage = ({
  List<String> ids,
  Map<int, Map<String, double>> summen,
});

H2HGrundlage h2hGrundlage({
  required FantasyLeague league,
  required List<FantasyManager> managers,
  required List<RosterEntry> roster,
  required List<FantasyLineup> lineups,
  required Map<String, FantasyPlayer> playerById,
  required Map<int, Map<String, PlayerMatchStats>> seasonStats,
  required List<int> abgepfiffen,
}) {
  // Stabile Reihenfolge (Draft-Position, dann User-ID) für den Round-Robin.
  final ids = managers.map((m) => m.userId).toList()
    ..sort((a, b) {
      final ma = managers.firstWhere((m) => m.userId == a);
      final mb = managers.firstWhere((m) => m.userId == b);
      final pa = ma.draftPosition ?? 1 << 30;
      final pb = mb.draftPosition ?? 1 << 30;
      return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
    });

  // **Nur abgepfiffene Spieltage.** Ein laufender Spieltag trägt schon mittags
  // Zwischenstände, und eine Bilanz ist ein Ergebnis.
  final fertig = gewerteteRunden(abgepfiffen, seasonStats.keys);
  final summen = <int, Map<String, double>>{
    for (final entry in seasonStats.entries)
      if (fertig.contains(entry.key))
        entry.key: effectiveTotalsForRound(
          stats: entry.value,
          round: entry.key,
          managers: managers,
          roster: roster,
          playerById: playerById,
          lineups: lineups,
          scoring: league.scoring,
          rosterConfig: league.roster,
        ),
  };
  return (ids: ids, summen: summen);
}
