import 'package:flutter/material.dart';

/// **Die Schriftskala der App — eine Leiter statt Einzelentscheidungen.**
///
/// Vorher standen 224 hartkodierte `fontSize`-Werte in über zwanzig
/// verschiedenen Größen im Code, darunter Halbschritte wie 12,5 · 11,5 · 15,5.
/// Aus zwei Metern Abstand sieht das aus wie „unpoliert", und genau so wurde
/// es auch gemeldet: Es gibt keine Hierarchie, die man wiedererkennt, sondern
/// an jeder Stelle eine neue Zahl.
///
/// Die Stufen sind an dem ausgerichtet, was die App ohnehin benutzt (11, 12,
/// 13 und 14 machen zusammen die Hälfte aller Vorkommen aus) — es ist keine
/// erfundene Skala, sondern die vorhandene, aufgeräumt.
///
/// **Barlow Condensed ist schmal**, deshalb liegen die Stufen enger
/// beieinander als bei einer normalen Grotesk: Was bei 16 Punkt in Inter
/// deutlich größer wirkt als 14, unterscheidet sich hier kaum.
abstract final class Schrift {
  /// Die große Zahl: Anstoßzeit auf der Kopfkarte, Punktestand im Duell.
  static const anzeige = 34.0;

  /// Schirm-Überschrift (H1) — in der AppBar.
  static const h1 = 24.0;

  /// Abschnitts-Überschrift (H2): Kartentitel, Blattüberschriften.
  static const h2 = 20.0;

  /// H3: die Überschrift innerhalb einer Karte.
  static const h3 = 18.0;

  /// Betonter Fließtext, Zeilenüberschriften.
  static const titel = 16.0;

  /// Fließtext.
  static const koerper = 14.0;

  /// Leiser Fließtext, Untertitel einer Zeile.
  static const koerperKlein = 13.0;

  /// Beschriftung: Pillen, Knöpfe, Tabellenköpfe.
  static const marke = 12.0;

  /// Kleingedrucktes: Zusätze, Zeitangaben, Hinweise.
  static const klein = 11.0;

  /// Versal-Marken und Zähler. Darunter wird nichts mehr gelesen, es wird
  /// erkannt.
  static const winzig = 10.0;

  /// **Zeichen, kein Text**: Initialen in einem Wappen, ein Länderkürzel, der
  /// Pick-Code in einer Draft-Zelle. Diese Stufe existiert, weil sie in der
  /// App wirklich gebraucht wird — in einen 26 Punkte großen Kreis passt
  /// nichts Größeres. Sie ist bewusst die Ausnahme und nicht für Sätze da.
  static const mikro = 9.0;

  /// Die Textleiter. Der Wächtertest prüft dagegen.
  static const alle = <double>[
    mikro, winzig, klein, marke, koerperKlein, koerper, titel, h3, h2, h1,
  ];

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
        fontFamily: 'BarlowCondensed',
        fontSize: groesse,
        fontWeight: gewicht,
        height: hoehe,
        letterSpacing: sperrung,
        color: farbe ?? aufFlaeche,
      );

  return TextTheme(
    displayLarge: s(Schrift.anzeige, FontWeight.w800, hoehe: 1.05),
    displayMedium: s(28, FontWeight.w800, hoehe: 1.1),
    headlineLarge: s(Schrift.h1, FontWeight.w800, sperrung: -0.4),
    headlineMedium: s(Schrift.h2, FontWeight.w700),
    headlineSmall: s(Schrift.h3, FontWeight.w700),
    titleLarge: s(Schrift.h3, FontWeight.w700),
    titleMedium: s(Schrift.titel, FontWeight.w700),
    titleSmall: s(Schrift.koerper, FontWeight.w700),
    bodyLarge: s(Schrift.titel, FontWeight.w400, hoehe: 1.3),
    bodyMedium: s(Schrift.koerper, FontWeight.w400, hoehe: 1.3),
    bodySmall: s(Schrift.koerperKlein, FontWeight.w400,
        farbe: leise, hoehe: 1.35),
    labelLarge: s(Schrift.koerperKlein, FontWeight.w700),
    labelMedium: s(Schrift.marke, FontWeight.w600),
    labelSmall: s(Schrift.klein, FontWeight.w700,
        farbe: leise, sperrung: 0.6),
  );
}
