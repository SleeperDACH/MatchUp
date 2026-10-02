/// **Aus zwei Prognosen eine Gewinnwahrscheinlichkeit.**
///
/// Gewünscht: „ein Prozentsatzregler, der die Gewinnwahrscheinlichkeit jeder
/// Seite einfügt." Der naheliegende Weg wäre der **Punkteanteil**
/// (`heim / (heim + gast)`) — und der ist falsch. Er sagt bei 228 gegen 190
/// „55 %", obwohl 38 Punkte Vorsprung in dieser Wertung eine ziemlich klare
/// Sache sind; und bei 2 gegen 1 sagt er dasselbe wie bei 200 gegen 100.
/// Genau dieses Etikett („Punkteanteil") hing hier schon einmal unter einem
/// Balken und ist geflogen, weil es nichts maß.
///
/// **Was eine Wahrscheinlichkeit braucht, ist ein Maß für die Streuung.** Ob
/// 38 Punkte Vorsprung viel sind, hängt davon ab, wie stark eine Wochensumme
/// um ihren Erwartungswert schwankt. Das lässt sich in dieser Liga **messen**:
/// [streuung] rechnet die Standardabweichung der tatsächlich erzielten
/// Wochensummen aus, [siegchance] setzt die Differenz der Prognosen dazu ins
/// Verhältnis.
///
/// **Drei Annahmen, die man kennen muss:**
///
/// * **Die beiden Summen werden als unabhängig behandelt.** Das stimmt nicht
///   ganz — beide Elfen schöpfen aus demselben Spielerpool, und an einem Tag
///   mit vielen Toren punkten alle. Die Differenz streut dadurch etwas weniger
///   als `σ·√2`, die Anzeige ist also eher zu vorsichtig als zu forsch.
/// * **Gerechnet wird über die Liga, nicht je Manager.** Ein einzelner Manager
///   hat nach fünf Spieltagen fünf Werte; das ist zu wenig für eine eigene
///   Streuung. Die gepoolte Streuung über alle Manager ist stabiler und für
///   diese Frage genau genug.
/// * **Ohne Historie gibt es keine Zahl.** Vor dem zweiten gewerteten Spieltag
///   ist nichts zu messen, und eine erfundene 50/50-Anzeige wäre eine Aussage,
///   die niemand gemacht hat — dieselbe Regel wie beim Strich statt der Null.
///   Dann liefern beide Funktionen `null`, und das Band bleibt weg.
library;

import 'dart:math' as math;

/// Standardabweichung der erzielten Wochensummen, oder `null`.
///
/// [totalsByRound] ist `Runde → Manager → Punkte`, **nur über gewertete
/// Spieltage** (der Aufrufer filtert mit `gewerteteRunden`; ein laufender
/// Spieltag trägt mittags Zwischenstände und würde die Streuung nach unten
/// ziehen).
///
/// Ein Spielfreier bekommt in dieser Liga keine Zeile, steht also nicht drin;
/// Nullsummen von Managern, die nie aufgestellt haben, sind dagegen echte
/// Werte und zählen mit — sie sind Teil der Streuung dieser Liga.
double? streuung(Map<int, Map<String, double>> totalsByRound) {
  final werte = <double>[
    for (final runde in totalsByRound.values) ...runde.values,
  ];
  // Zwei Werte sind das Minimum, aus dem sich überhaupt eine Abweichung
  // bilden lässt; darunter ist jede Zahl geraten.
  if (werte.length < 2) return null;

  final mittel = werte.reduce((a, b) => a + b) / werte.length;
  final quadrate = werte.fold<double>(
    0,
    (summe, w) => summe + (w - mittel) * (w - mittel),
  );
  // Stichprobenvarianz (n−1): Wir messen an einer Stichprobe von Spieltagen,
  // nicht an der Grundgesamtheit aller denkbaren.
  final sd = math.sqrt(quadrate / (werte.length - 1));
  // Eine Streuung von 0 entsteht, wenn alle Summen gleich sind (im echten
  // Betrieb praktisch nie, im Test schon). Damit ließe sich nicht teilen.
  return sd > 0 ? sd : null;
}

/// Wahrscheinlichkeit, dass **die Heimseite** gewinnt — 0 bis 1, oder `null`.
///
/// [heim] und [gast] sind die prognostizierten Punkte, [wochenStreuung] das
/// Ergebnis von [streuung].
///
/// Gerechnet wird mit der logistischen Näherung der Normalverteilung: Die
/// Differenz zweier Wochensummen streut mit `σ·√2`, und die logistische
/// Kurve trifft die Normalverteilung am besten bei einer Skala von
/// `σ_diff · √3 / π`. Das ist kein Beiwerk — mit der falschen Skala sagt
/// dieselbe Differenz einmal 55 % und einmal 95 %.
double? siegchance({
  required double heim,
  required double gast,
  required double? wochenStreuung,
}) {
  if (wochenStreuung == null || wochenStreuung <= 0) return null;

  final streuungDerDifferenz = wochenStreuung * math.sqrt2;
  final skala = streuungDerDifferenz * math.sqrt(3) / math.pi;
  final p = 1 / (1 + math.exp(-(heim - gast) / skala));

  // Gegen Rundungsausreißer an den Rändern: Eine 0 % oder 100 % gibt es in
  // diesem Spiel nicht, und sie zu behaupten wäre schlimmer als eine 1 %.
  return p.clamp(0.01, 0.99);
}
