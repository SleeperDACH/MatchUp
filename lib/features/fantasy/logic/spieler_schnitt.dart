/// **Was ein Spieler im Schnitt bringt.**
///
/// Gewünscht: „eine Anzeige für durchschnittliche Minuten und durchschnittliche
/// Punkte des jeweiligen Spielers".
///
/// Die Frage dahinter ist eine Kaufentscheidung, und dafür sind **zwei**
/// Schnitte verschieden nützlich:
///
/// * **je Spieltag** — über alle gewerteten Spieltage, ein Nichteinsatz zählt
///   als null. Das ist der ehrliche Erwartungswert: Wer die halbe Saison
///   verletzt war, ist im Schnitt schlechter, auch wenn er stark spielt, wenn
///   er spielt.
/// * **je Einsatz** — nur Spieltage mit Minuten. Das sagt, was er kann, wenn
///   er auf dem Platz steht.
///
/// Beide zu zeigen ist keine Unentschlossenheit: Der Unterschied zwischen
/// ihnen **ist** die Auskunft (ein Stammspieler hat zwei gleiche Zahlen, ein
/// Ergänzungsspieler zwei sehr verschiedene).
library;

import 'fantasy_scoring_engine.dart';
import 'fantasy_scoring_rules.dart';
import '../models/fantasy_models.dart';

class SpielerSchnitt {
  const SpielerSchnitt({
    required this.spieltage,
    required this.einsaetze,
    required this.minutenJeSpieltag,
    required this.punkteJeSpieltag,
    required this.minutenJeEinsatz,
    required this.punkteJeEinsatz,
  });

  /// Gewertete Spieltage insgesamt — der Nenner des ersten Schnitts.
  final int spieltage;

  /// Davon mit Spielzeit.
  final int einsaetze;

  final double minutenJeSpieltag;
  final double punkteJeSpieltag;

  /// `null`, wenn er noch keine Minute gespielt hat — dann gibt es nichts zu
  /// mitteln, und eine 0 wäre eine Aussage, die niemand gemacht hat.
  final double? minutenJeEinsatz;
  final double? punkteJeEinsatz;

  /// Gibt es überhaupt etwas zu zeigen?
  bool get hatDaten => spieltage > 0;
}

/// Schnitt eines Spielers über die bereits gewerteten Spieltage.
///
/// [saison] ist `Spieltag → Spieler → Werte`. **Als Spieltag zählt nur, was
/// überhaupt gewertet wurde** — erkennbar daran, dass irgendein Spieler dort
/// Daten hat. Ein Spieltag, der erst kommt, darf den Schnitt nicht drücken;
/// genau daran hing schon einmal ein Fehler an anderer Stelle („noch nicht
/// gespielt ist kein Nullpunktespiel").
SpielerSchnitt spielerSchnitt({
  required Map<int, Map<String, PlayerMatchStats>> saison,
  required String spielerId,
  required PlayerPosition position,
  required FantasyScoringRules regeln,
}) {
  var spieltage = 0;
  var einsaetze = 0;
  var minuten = 0;
  var punkte = 0.0;
  var minutenMitEinsatz = 0;
  var punkteMitEinsatz = 0.0;

  for (final runde in saison.values) {
    if (runde.isEmpty) continue; // Spieltag noch nicht gewertet
    spieltage++;
    final s = runde[spielerId];
    if (s == null) continue; // gewertet, aber ohne ihn: zählt als Null
    final p = scorePlayer(s, position, regeln);
    minuten += s.minutes;
    punkte += p;
    if (s.minutes > 0) {
      einsaetze++;
      minutenMitEinsatz += s.minutes;
      punkteMitEinsatz += p;
    }
  }

  return SpielerSchnitt(
    spieltage: spieltage,
    einsaetze: einsaetze,
    minutenJeSpieltag: spieltage == 0 ? 0 : minuten / spieltage,
    punkteJeSpieltag: spieltage == 0 ? 0 : punkte / spieltage,
    minutenJeEinsatz:
        einsaetze == 0 ? null : minutenMitEinsatz / einsaetze,
    punkteJeEinsatz: einsaetze == 0 ? null : punkteMitEinsatz / einsaetze,
  );
}
