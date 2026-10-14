/// **Wo eine Elf am Ende des Spieltags voraussichtlich landet.**
///
/// Vor dem Anpfiff gibt es die Prognose (`projektion.dart`): Summe der Schnitte.
/// Sobald gespielt wird, ist ein Teil davon keine Schätzung mehr, sondern
/// Ergebnis. Die Hochrechnung setzt beides zusammen — **wer fertig ist, zählt
/// mit seinen echten Punkten, wer noch spielt, mit seinen Punkten plus dem
/// erwarteten Rest, wer noch nicht dran war, mit seinem Schnitt.**
///
/// Vorbild ist der MatchUp-Kasten bei Sleeper: groß der Stand, klein darunter,
/// wo es hinläuft, und eine Siegchance, die sich mit jedem Abpfiff schärft.
/// Gewünscht ausdrücklich mit dem Satz, dass „wir das System der Prognose noch
/// weiter ausbauen" — deshalb steht hier jede Annahme einzeln und benannt.
///
/// **Die Annahmen:**
///
/// * **Der Rest eines laufenden Spiels ist anteilig.** Wer nach 60 Minuten bei
///   4 Punkten steht und im Schnitt 9 holt, bekommt ein Drittel der 9 dazu.
///   Das ist grob — Einsatzpunkte fallen am Anfang an, Tore irgendwann —, aber
///   es ist stetig: Die Zahl springt beim Abpfiff nicht.
/// * **Die Spielminute wird aus der Uhr geschätzt**, nicht gemeldet. Die
///   Listen des Spielplans tragen sie bewusst nicht (siehe Live-Tab). Nach dem
///   Anpfiff zählt die Uhr, ab Minute 45 sind 15 Minuten Pause abgezogen, und
///   bei 90 ist Schluss — Nachspielzeit bleibt unberücksichtigt.
/// * **Ein Ausfall zählt mit null**, solange sein Spiel nicht angepfiffen ist.
///   Anders als in der Prognose, die ihn auslässt: Dort ist die Frage „was
///   bringen die, die spielen können", hier ist es „wo landet diese Elf".
library;

import 'dart:math' as math;

import 'siegchance.dart';

/// Wie weit das Spiel eines Spielers ist.
enum SpielLage { offen, laeuft, fertig, ohneSpiel }

/// Eine Zeile der Hochrechnung: was ein Spieler schon hat und noch erwarten
/// lässt.
class HochrechnungsPosten {
  const HochrechnungsPosten({
    required this.lage,
    required this.punkte,
    required this.schnitt,
    this.anpfiff,
    this.faellt = false,
  });

  final SpielLage lage;

  /// Bisher erzielte Punkte (0, solange nicht gespielt).
  final double punkte;

  /// Erwartete Punkte für ein ganzes Spiel (Schnitt je Spieltag).
  final double schnitt;

  /// Anpfiff seines Vereins — für den Restanteil eines laufenden Spiels.
  final DateTime? anpfiff;

  /// Gemeldeter Ausfall (verletzt, gesperrt).
  final bool faellt;
}

class Hochrechnung {
  const Hochrechnung({
    required this.stand,
    required this.erwartet,
    required this.offen,
    required this.voll,
  });

  /// Bisher erzielte Punkte der Elf.
  final double stand;

  /// Voraussichtliche Endpunktzahl: Stand plus erwarteter Rest.
  final double erwartet;

  /// Noch erwartete Punkte (erwartet − Stand).
  final double offen;

  /// Erwartung für den ganzen Spieltag ohne jedes Ergebnis — die Bezugsgröße
  /// dafür, wie viel noch offen ist.
  final double voll;

  /// Anteil des Spieltags, der noch aussteht (0 = alles gespielt).
  double get offenAnteil => voll <= 0 ? 0 : (offen / voll).clamp(0.0, 1.0);
}

/// Geschätzte Spielminute aus der Zeit seit dem Anpfiff (0–90).
double geschaetzteMinute(DateTime anpfiff, DateTime jetzt) {
  final seit = jetzt.difference(anpfiff).inSeconds / 60.0;
  if (seit <= 0) return 0;
  // Bis zur Pause läuft die Uhr mit, danach 15 Minuten Halbzeit abziehen.
  final minute = seit <= 45 ? seit : math.max(45.0, seit - 15);
  return minute.clamp(0.0, 90.0);
}

Hochrechnung hochrechnung(
  Iterable<HochrechnungsPosten> elf, {
  required DateTime jetzt,
}) {
  var stand = 0.0;
  var offen = 0.0;
  var voll = 0.0;
  for (final p in elf) {
    voll += p.faellt ? 0 : p.schnitt;
    switch (p.lage) {
      case SpielLage.fertig:
        stand += p.punkte;
      case SpielLage.laeuft:
        stand += p.punkte;
        final minute =
            p.anpfiff == null ? 45.0 : geschaetzteMinute(p.anpfiff!, jetzt);
        offen += p.schnitt * (1 - minute / 90);
      case SpielLage.offen:
        offen += p.faellt ? 0 : p.schnitt;
      case SpielLage.ohneSpiel:
        // Sein Verein spielt an diesem Spieltag nicht — er bringt nichts.
        break;
    }
  }
  return Hochrechnung(
    stand: stand,
    erwartet: stand + offen,
    offen: offen,
    voll: voll,
  );
}

/// Siegchance der Heimseite während des Spieltags (0–1) oder `null`.
///
/// **Die Unsicherheit schrumpft mit dem, was noch offen ist.** Vor dem Anpfiff
/// streut eine Wochensumme mit der gemessenen Streuung der Liga; ist die Hälfte
/// gespielt, streut nur noch der Rest. Angenommen ist, dass die Varianz
/// proportional zum offenen Anteil ist — die Standardabweichung also mit
/// dessen Wurzel. Damit gehen die Prozente gegen Ende des Spieltags von selbst
/// gegen 0 und 100, statt bis zum Abpfiff bei 70/30 stehen zu bleiben.
///
/// **Ist alles gespielt, ist es keine Wahrscheinlichkeit mehr**: 1, 0 oder ½.
double? siegchanceLive({
  required Hochrechnung heim,
  required Hochrechnung gast,
  required double? wochenStreuung,
}) {
  final gesamtVoll = heim.voll + gast.voll;
  final anteil = gesamtVoll <= 0
      ? 0.0
      : ((heim.offen + gast.offen) / gesamtVoll).clamp(0.0, 1.0);
  if (anteil <= 0) {
    if (heim.erwartet > gast.erwartet) return 1;
    if (heim.erwartet < gast.erwartet) return 0;
    return 0.5;
  }
  if (wochenStreuung == null || wochenStreuung <= 0) return null;
  return siegchance(
    heim: heim.erwartet,
    gast: gast.erwartet,
    wochenStreuung: wochenStreuung * math.sqrt(anteil),
  );
}
