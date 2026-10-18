import 'package:flutter/material.dart';

/// **Die Schriftskala der App — eine Leiter statt Einzelentscheidungen.**
///
/// Vorher standen 224 hartkodierte `fontSize`-Werte in über zwanzig
/// verschiedenen Größen im Code, darunter Halbschritte wie 12,5 · 11,5 · 15,5.
/// Aus zwei Metern Abstand sieht das aus wie „unpoliert", und genau so wurde
/// es auch gemeldet: Es gibt keine Hierarchie, die man wiedererkennt, sondern
/// an jeder Stelle eine neue Zahl.
///
/// Seit dem 15.10.2026 sind es **vier** Stufen statt elf (siehe [Schrift.gross]
/// und Nachbarn) — die alte Leiter war aufgeräumt, aber zu fein, um als
/// Hierarchie zu wirken.
abstract final class Schrift {
  /// **Die Schriftfamilie — an genau einer Stelle.** Jeder Stil im Theme
  /// nennt sie über diese Konstante; ein Wechsel ist damit eine Zeile hier
  /// plus `pubspec.yaml` und `test/support/schrift.dart`.
  static const familie = 'Inter';

  /// **Vier Stufen, nicht elf** (Design-Ideen Punkt 2, 15.10.2026).
  ///
  /// Die Leiter davor hatte elf Stufen von 9 bis 34 (h1, h2, h3, titel,
  /// koerper, koerperKlein, marke, klein, winzig …). Jede war begründet, und
  /// zusammen ergaben sie trotzdem keine Hierarchie, die man wiedererkennt:
  /// zwischen 13 und 14 oder 10, 11 und 12 sieht niemand einen Unterschied,
  /// er sieht nur, dass nichts gleich aussieht. Jetzt gibt es vier Rollen:
  ///
  /// | Stufe | Größe | wofür |
  /// |---|---|---|
  /// | [gross] | 24 | Punktestände, die eine Zahl, um die es geht |
  /// | [titel] | 17 | Überschriften, Namen, Zahlen in Tabellen |
  /// | [text] | 14 | Fließtext, Zeilen, Untertitel (leiser in der Farbe) |
  /// | [label] | 11 | Marken in Versalien, Zusätze, Zähler |
  ///
  /// Abgestuft wird darunter über **Gewicht und Farbe**, nicht über die
  /// Größe: ein Untertitel ist `text` in `onSurfaceVariant`, keine 13.
  static const gross = 24.0;
  static const titel = 17.0;
  static const text = 14.0;
  static const label = 11.0;

  /// Die eine große Anzeigezahl: Anstoßzeit auf der Kopfkarte.
  static const anzeige = 34.0;

  /// **Zeichen, kein Text**: Initialen in einem Wappen, ein Länderkürzel, der
  /// Pick-Code in einer Draft-Zelle. In einen 26 Punkte großen Kreis passt
  /// nichts Größeres. Bewusst die Ausnahme und nicht für Sätze da.
  static const mikro = 9.0;

  /// Die Textleiter. Der Wächtertest prüft dagegen.
  static const alle = <double>[mikro, label, text, titel, gross];

  /// **Anzeigegrößen** — große Zahlen, die für sich stehen: die Anstoßzeit auf
  /// der Kopfkarte (38), der Punktestand im Duell (32), die Wortmarke beim
  /// Start (40). Sie folgen keiner Leiter, weil es je Stelle genau eine gibt
  /// und ihre Größe aus dem Platz kommt, den sie füllen sollen.
  static const anzeigen = <double>[28, 32, 34, 38, 40, 42, 52];
}

/// **Die Abstandsleiter — ein 8er-Raster mit halber Stufe.**
///
/// Padding und Margin standen ebenso frei im Code (4, 6, 7, 10, 12, 14, 16,
/// 18 …). Ein Raster macht aus zufälligen Abständen ein System; die halbe
/// Stufe (4) bleibt, weil zwischen einem Symbol und seiner Beschriftung acht
/// Punkte zu viel sind.
abstract final class Abstand {
  static const halb = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
}

/// Die Textstile der App, aus der Skala gebaut.
///
/// **Jeder trägt die Schriftfamilie ausdrücklich.** Ein Stil in einem
/// Theme-Feld *ersetzt* den aufgelösten Stil, er ergänzt ihn nicht — wer die
/// Familie dort vergisst, bekommt stumm die Systemschrift. Das ist in diesem
/// Projekt dreimal passiert: in den Fantasy-Einstellungen, in den Reitern und
/// zuletzt in `chipTheme`, wo jeder Material-Chip in Roboto stand.
TextTheme matchUpTextTheme(Color aufFlaeche, Color leise) {
  TextStyle s(double groesse, FontWeight gewicht,
          {Color? farbe, double? hoehe, double? sperrung}) =>
      TextStyle(
        fontFamily: Schrift.familie,
        fontSize: groesse,
        fontWeight: gewicht,
        height: hoehe,
        letterSpacing: sperrung,
        color: farbe ?? aufFlaeche,
      );

  return TextTheme(
    displayLarge: s(Schrift.anzeige, FontWeight.w800, hoehe: 1.05),
    displayMedium: s(28, FontWeight.w800, hoehe: 1.1),
    headlineLarge: s(Schrift.gross, FontWeight.w800, sperrung: -0.4),
    headlineMedium: s(Schrift.titel, FontWeight.w800),
    headlineSmall: s(Schrift.titel, FontWeight.w700),
    titleLarge: s(Schrift.titel, FontWeight.w700),
    titleMedium: s(Schrift.titel, FontWeight.w700),
    titleSmall: s(Schrift.text, FontWeight.w700),
    bodyLarge: s(Schrift.titel, FontWeight.w400, hoehe: 1.3),
    bodyMedium: s(Schrift.text, FontWeight.w400, hoehe: 1.3),
    bodySmall: s(Schrift.text, FontWeight.w400,
        farbe: leise, hoehe: 1.35),
    labelLarge: s(Schrift.text, FontWeight.w700),
    labelMedium: s(Schrift.label, FontWeight.w700, sperrung: 0.3),
    labelSmall: s(Schrift.label, FontWeight.w700,
        farbe: leise, sperrung: 0.6),
  );
}
