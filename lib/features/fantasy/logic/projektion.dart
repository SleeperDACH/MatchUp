/// **Was die aufgestellte Elf am kommenden Spieltag voraussichtlich bringt.**
///
/// Gewünscht: „zwischen den Spieltagen eine Projected Punktzahl, berechnet aus
/// den durchschnittlichen Punkten aller in der Startelf stehenden Spieler. Es
/// gilt nur die Regel, dass ein Spieler, der für das kommende Spiel verletzt
/// oder gesperrt ist, nicht mit reingerechnet wird."
///
/// Drei Entscheidungen stecken darin, und jede hätte auch anders ausfallen
/// können:
///
/// * **Summe der Schnitte, nicht Schnitt der Schnitte.** Gefragt ist, was die
///   *Mannschaft* holt. Der Mittelwert über elf Spieler läge bei rund 14 und
///   wäre keine Punktzahl, die man mit einem Gegner vergleichen kann.
/// * **Der Schnitt je Spieltag, nicht je Einsatz.** [spielerSchnitt] rechnet
///   beides; je Spieltag zählt ein Nichteinsatz als Null und ist damit der
///   ehrliche Erwartungswert. Je Einsatz sagt, was einer kann, *wenn* er
///   spielt — als Prognose wäre das systematisch zu optimistisch.
/// * **Ausgelassen heißt weggelassen, nicht null.** Ein verletzter Spieler
///   zieht die Prognose nicht nach unten, er kommt gar nicht vor. Die Zahl
///   beantwortet „was bringen die, die spielen können" — und sagt über
///   [ausgelassen] dazu, auf wie vielen Spielern sie beruht. Ihn mit 0
///   einzurechnen wäre die andere denkbare Lesart und würde eine Elf mit zwei
///   Verletzten schlechter aussehen lassen, als sie am Samstag antritt.
///
/// **Ohne gewertete Spieltage gibt es keine Prognose.** Vor dem ersten
/// Spieltag ist jeder Schnitt 0; eine 0 hinzuschreiben wäre eine Aussage, die
/// niemand gemacht hat — dieselbe Regel wie beim Strich statt der Null in der
/// Punktebox. Dafür steht [hatDaten].
library;

import '../models/fantasy_models.dart';
import '../models/player_absence.dart';
import 'fantasy_scoring_engine.dart';
import 'fantasy_scoring_rules.dart';
import 'spieler_schnitt.dart';

class Projektion {
  const Projektion({
    required this.punkte,
    required this.gezaehlt,
    required this.ausgelassen,
    required this.spieltage,
  });

  /// Summe der Schnitte aller eingerechneten Spieler.
  final double punkte;

  /// Wie viele Spieler in die Summe eingegangen sind.
  final int gezaehlt;

  /// Wie viele wegen Verletzung oder Sperre übersprungen wurden.
  final int ausgelassen;

  /// Gewertete Spieltage, auf denen die Schnitte beruhen.
  final int spieltage;

  /// Gibt es überhaupt eine Grundlage? Vor dem ersten gewerteten Spieltag
  /// nicht — dann steht ein Strich da, keine Null.
  bool get hatDaten => spieltage > 0 && gezaehlt > 0;
}

/// Prognose für [elf] auf Grundlage der bisher gewerteten Spieltage.
///
/// [ausfaelle] ist `Spieler-ID → Ausfall`, so wie der `absencesProvider` sie
/// liefert; wer darin steht, wird übersprungen. Die Sicht dahinter
/// (`player_absences_v`) hat überholte Meldungen bereits aussortiert — ein
/// Spieler, der seit dem gemeldeten Ausfall wieder gespielt hat, steht dort
/// gar nicht mehr drin, und genau deshalb wird hier nicht zusätzlich gefiltert.
Projektion projektion({
  required Iterable<FantasyPlayer> elf,
  required Map<int, Map<String, PlayerMatchStats>> saison,
  required FantasyScoringRules regeln,
  required Map<String, PlayerAbsence> ausfaelle,
}) {
  // **Als Spieltag zählt nur, was gewertet wurde** — dieselbe Regel wie in
  // `spielerSchnitt`, und sie muss dieselbe bleiben: Sie ist der Nenner, aus
  // dem jeder einzelne Schnitt entsteht.
  final spieltage = saison.values.where((r) => r.isNotEmpty).length;

  var summe = 0.0;
  var gezaehlt = 0;
  var ausgelassen = 0;

  for (final p in elf) {
    if (ausfaelle.containsKey(p.id)) {
      ausgelassen++;
      continue;
    }
    summe += spielerSchnitt(
      saison: saison,
      spielerId: p.id,
      position: p.position,
      regeln: regeln,
    ).punkteJeSpieltag;
    gezaehlt++;
  }

  return Projektion(
    punkte: summe,
    gezaehlt: gezaehlt,
    ausgelassen: ausgelassen,
    spieltage: spieltage,
  );
}
