import '../models/fantasy_models.dart';
import 'fantasy_scoring_engine.dart';
import 'fantasy_scoring_rules.dart';

/// **Was ein Spieler in der laufenden Saison geholt hat** — je Spieler die
/// Summe über alle gewerteten Spieltage, mit dem Scoring *dieser* Liga.
///
/// Zwei Ligen mit verschiedenen Regeln kommen für denselben Spieler auf
/// verschiedene Zahlen; die Reihenfolge einer Liste gehört deshalb zur Liga
/// und nicht zum Spieler. Genau deshalb steht hier `regeln` und nicht ein
/// fester Satz.
///
/// Ein Spieler ohne einen einzigen Einsatz taucht **nicht** in der Karte auf.
/// Das ist ein Unterschied zu „null Punkte": Wer verletzt fehlte, hat nichts
/// geholt; wer gar nicht im Datensatz steht, ist unbekannt. Wer sortiert, darf
/// beides gleich behandeln — wer etwas hinschreibt, nicht.
Map<String, double> saisonPunkte({
  required Map<int, Map<String, PlayerMatchStats>> saison,
  required Map<String, FantasyPlayer> spieler,
  required FantasyScoringRules regeln,
}) {
  final summe = <String, double>{};
  for (final runde in saison.values) {
    for (final MapEntry(key: id, value: stats) in runde.entries) {
      final p = spieler[id];
      if (p == null) continue;
      summe[id] = (summe[id] ?? 0) + scorePlayer(stats, p.position, regeln);
    }
  }
  return summe;
}

/// Die Reihung der Free Agency: **erst die freien Spieler, dann die in
/// Kadern** — und innerhalb jeder Gruppe die besten zuerst.
///
/// Die Trennung ist keine Kosmetik, sondern die Handlung: Oben steht, was man
/// sofort holen kann, darunter, wofür man jemanden fragen muss. Wären beide
/// Gruppen nach Punkten gemischt, stünde der beste Spieler der Liga ganz oben
/// — und wäre nicht zu haben.
///
/// Gleichstand geht nach Namen, damit die Liste sich zwischen zwei Aufbauten
/// nicht umsortiert.
List<FantasyPlayer> freieZuerst(
  List<FantasyPlayer> spieler, {
  required Set<String> inKadern,
  required Map<String, double> punkte,
}) {
  final sortiert = [...spieler]..sort((a, b) {
      final ak = inKadern.contains(a.id) ? 1 : 0;
      final bk = inKadern.contains(b.id) ? 1 : 0;
      if (ak != bk) return ak - bk;
      final pa = punkte[a.id] ?? 0;
      final pb = punkte[b.id] ?? 0;
      return pa != pb ? pb.compareTo(pa) : a.name.compareTo(b.name);
    });
  return sortiert;
}
