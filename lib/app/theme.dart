import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'farben.dart';

import 'typografie.dart';

/// MatchUp-Markenfarben.
class MatchUpColors {
  const MatchUpColors._();

  /// **Schwarz.** Der Grund der App, seit dem 03.09.2026 ohne den früheren
  /// Blaustich (`#12141C`) — auf Ansage: „Die gesamte App wechselt auf
  /// schwarzen Hintergrund."
  ///
  /// Er ist zugleich die Schrift- und Symbolfarbe **auf** hellen Flächen
  /// (weißer Hauptknopf, gefüllte Positionsmarken); dort war der Blaustich nie
  /// zu sehen, und Schwarz auf Weiß ist der stärkere Kontrast.
  static const base = Color(0xFF000000);

  /// Marken-/Primärakzent (Logo-„Up", Buttons, aktive Zustände).
  static const green = Color(0xFF4ADE6A);

  /// Signalfarbe: Fehler/Negativ und Live-Spiele.
  static const red = Color(0xFFF23030);

  /// Text/Vordergrund auf dunklem Grund.
  static const snow = Color(0xFFEDEFF4);

  // Abgestufte Flächen über [base] für Tiefe (Karten, Leisten, Kopfzeilen).
  //
  // **Neutrale Graustufen, kein Blau mehr.** Auf einem schwarzen Grund fiel
  // der alte Blaustich der Karten (`#1A1D27`) auf: Die Flächen schienen zu
  // leuchten, statt über dem Grund zu liegen. Die Leiter steigt jetzt in
  // gleichen Kanälen — und weil kein Kanal führt, bleibt sie auch neutral,
  // wenn Material 3 seine Seed-Farbe einmischen will.
  static const _surfaceCard = Color(0xFF121212);
  static const _surfaceHigh = Color(0xFF232323);
  static const _surfaceLowest = Color(0xFF050505);
  static const _surfaceLow = Color(0xFF0D0D0D);
  static const _surfaceMid = Color(0xFF1A1A1A);
  static const _divider = Color(0xFF2A2A2A);

  /// Gedämpftes Snow für Sekundärtext. Ebenfalls entblaut: Auf Schwarz las
  /// sich der alte Ton (`#A6ACBA`) als kühles Grau-Blau.
  static const _mutedText = Color(0xFFAAAAAA);

  // **Heller Modus (seit 29.10.2026): reines Apple-Weiß als Grund.** Die
  // Leiter steigt von dort in neutralen Grautönen *nach unten* — Karten
  // liegen als `#F2F2F7` (Apples `secondarySystemBackground`) auf Weiß, nicht
  // als Weiß auf Grau. Auf Dunkel trägt die Fläche die Tiefe; auf Hell genauso,
  // nur in der anderen Richtung. Kein Kanal führt, damit `fromSeed` auch hier
  // keinen Grünstich einschleppt (`flaechen_neutral_test`).
  static const _lightBg = Color(0xFFFFFFFF);
  static const _lightLowest = Color(0xFFFFFFFF);
  static const _lightLow = Color(0xFFFFFFFF);
  static const _lightCard = Color(0xFFF2F2F7);
  static const _lightMid = Color(0xFFEAEAEF);
  static const _lightHigh = Color(0xFFE3E3E8);
  static const _lightDim = Color(0xFFE5E5EA);
  static const _lightDivider = Color(0xFFD8D8DE);

  /// Sekundärtext auf Weiß — Apples `secondaryLabel`, 5,1:1.
  static const _lightMuted = Color(0xFF6E6E73);

  /// Schrift auf Weiß. Reines Schwarz wie Apples `label`.
  static const _lightText = Color(0xFF000000);
}

/// MatchUp-Theme für die gewünschte [brightness]. Dark bleibt der markante
/// „Base"-Look; Light ist die helle Variante mit denselben Akzenten (grün/rot).
ThemeData buildAppTheme({Brightness brightness = Brightness.dark}) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? MatchUpColors.base : MatchUpColors._lightBg;
  final cardColor = dark ? MatchUpColors._surfaceCard : MatchUpColors._lightCard;
  // Glasige Karten-Tönung: die Flächenfarbe leicht durchscheinend, damit der
  // Grund durchschimmert und ein feiner Licht-Rand die Kante fasst.
  final glassCard = (dark ? MatchUpColors._surfaceCard : MatchUpColors._lightCard)
      .withValues(alpha: dark ? 0.72 : 0.80);
  final glassBorder = dark
      ? Colors.white.withValues(alpha: 0.10)
      : MatchUpColors._lightDivider;
  final farben = dark ? MatchUpFarben.dunkel : MatchUpFarben.hell;
  // Schrift auf der Fläche und ihr Gegenstück (die Fläche unter einem
  // gefüllten Knopf). Im Dunkeln Snow auf Schwarz, im Hellen umgekehrt.
  final text = dark ? MatchUpColors.snow : MatchUpColors._lightText;

  final scheme = ColorScheme.fromSeed(
    seedColor: MatchUpColors.green,
    brightness: brightness,
  ).copyWith(
    // Auf Weiß ist das Markengrün als Schrift unlesbar (1,8:1) — `primary`
    // wird dort als Text und Symbol benutzt, also die dunklere Fassung.
    primary: farben.gruen,
    onPrimary: dark ? MatchUpColors.base : Colors.white,
    surface: bg,
    onSurface: text,
    onSurfaceVariant: dark ? MatchUpColors._mutedText : MatchUpColors._lightMuted,
    // **Die ganze Flächenleiter neutral halten, nicht nur die oberste Stufe.**
    //
    // `ColorScheme.fromSeed` mischt die Seed-Farbe in *jede*
    // `surfaceContainer*`-Stufe. Überschrieben war nur `surfaceContainerHighest`
    // — die übrigen vier kamen grün gestochen heraus, gemessen:
    // `surfaceContainerLow` = `#181D18` (Grünkanal am höchsten), während der
    // App-Grund `#12141C` blaustichig ist.
    //
    // Sichtbar wurde das an den **Spielerprofilen**: `showModalBottomSheet`
    // nimmt in Material 3 `surfaceContainerLow`, also lag das halbe Blatt auf
    // einer grünen Fläche. Der Drawer hatte denselben Fehler und bekam damals
    // eine eigene Fläche verpasst; das war die Behandlung eines Symptoms —
    // hier steht die Ursache.
    surfaceContainerLowest:
        dark ? MatchUpColors._surfaceLowest : MatchUpColors._lightLowest,
    surfaceContainerLow:
        dark ? MatchUpColors._surfaceLow : MatchUpColors._lightLow,
    surfaceContainer:
        dark ? MatchUpColors._surfaceCard : MatchUpColors._lightCard,
    surfaceContainerHigh:
        dark ? MatchUpColors._surfaceMid : MatchUpColors._lightMid,
    surfaceContainerHighest:
        dark ? MatchUpColors._surfaceHigh : MatchUpColors._lightHigh,
    // `surfaceDim` und `surfaceBright` gehören zur selben Leiter und wurden
    // beim ersten Anlauf übersehen — der Wächtertest hat sie gefunden.
    surfaceDim: dark ? MatchUpColors._surfaceLowest : MatchUpColors._lightDim,
    surfaceBright: dark ? MatchUpColors._surfaceMid : MatchUpColors._lightBg,
    error: farben.rot,
    onError: dark ? MatchUpColors.snow : Colors.white,
    outlineVariant: dark ? MatchUpColors._divider : MatchUpColors._lightDivider,
  );

  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: Schrift.familie,
    // **Eine Schriftskala statt Materials Vorgaben.** Ohne `textTheme` kommen
    // die Größen aus Material (bodyMedium 14, titleLarge 22 …) — eine Leiter,
    // die für eine normale Grotesk gedacht ist, nicht für eine schmale.
    // `Schrift` in `typografie.dart` trägt die Stufen; jeder Stil dort nennt
    // die Familie ausdrücklich, weil ein Theme-Stil den aufgelösten *ersetzt*.
    extensions: [farben],
    textTheme: matchUpTextTheme(
        text,
        dark ? MatchUpColors._mutedText : MatchUpColors._lightMuted),
    scaffoldBackgroundColor: bg,
    dividerColor: scheme.outlineVariant,
    appBarTheme: AppBarTheme(
      backgroundColor: bg.withValues(alpha: 0.0),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      // Statusleiste passend zum Grund: helle Symbole auf Schwarz, dunkle auf
      // Weiß — sonst stehen Uhrzeit und Akku weiß auf weiß.
      systemOverlayStyle:
          dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      // Auffälliger, „dicker" Titel in condensed Schrift — überall einheitlich
      // (wie die überarbeitete Liga-Kopfzeile, siehe VibrantLeagueTitle).
      titleTextStyle: TextStyle(
        fontFamily: Schrift.familie,
        fontWeight: FontWeight.w800,
        fontSize: Schrift.gross,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: glassCard,
      elevation: 0,
      // Feiner heller Rand gibt der Karte die Glaskante.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: glassBorder, width: 0.8),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    ),
    // Seitenmenü: **neutrale** Fläche. Ohne diese Angabe mischt Material 3 die
    // Seed-Farbe in den Drawer-Grund (`surfaceContainerLow`) — aus dem grünen
    // Seed wurde eine olivgrün gestochene Fläche, die zu keiner anderen
    // Oberfläche der App passte.
    drawerTheme: DrawerThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrimColor: Colors.black.withValues(alpha: dark ? 0.55 : 0.32),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
    ),
    // **Der gefüllte Hauptknopf ist hell, nicht grün.** Das Markengrün stand
    // auf rund neunzig Knöpfen quer durch die App — Anmelden, Liga erstellen,
    // Beitreten, Tipp speichern, Draft starten, Angebot senden. Damit sah die
    // Entscheidung eines Schirms aus wie jede andere Schaltfläche, und Grün
    // heißt in dieser App „hier läuft etwas". Ein Knopf läuft nicht; er wartet
    // auf einen Druck. Hell auf dunklem Grund ist der stärkste Kontrast, den
    // diese Oberfläche hat, ohne eine weitere Signalfarbe einzuführen.
    //
    // **Grün bleibt, wo es Zustimmung heißt** — beim Paar „Annehmen" gegen
    // „Ablehnen" (Trades, Freundschaftsanfragen, Beitritte). Dort steht es
    // gegen Rot, und ohne Grün verliert Rot sein Gegenüber. Diese Stellen
    // setzen ihre Farbe ausdrücklich.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: text,
        foregroundColor: bg,
        disabledBackgroundColor: scheme.surfaceContainerHigh,
        disabledForegroundColor: scheme.onSurfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        // Die Familie muss auch hier stehen — dieselbe Falle wie beim
        // Chip-Stil: Ein Stil in einem Theme-Feld ersetzt den aufgelösten.
        textStyle: const TextStyle(
          fontFamily: Schrift.familie,
          fontWeight: FontWeight.w800,
          fontSize: Schrift.titel,
          letterSpacing: 0.2,
        ),
      ),
    ),
    // **Auch hier ist der aktive Reiter weiß, nicht grün.** Die schwebende
    // Hauptleiste (`_GlassNavBar`) setzt ihre Farben selbst; dieses Theme
    // trägt die zweite Leiste, die es gibt — die im Tippspiel-Screen. Beide
    // sollen gleich aussehen, sonst heißt „ausgewählt" unten im Bild zweierlei.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      indicatorColor: farben.auswahlFlaeche,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? text
              : text.withValues(alpha: dark ? 0.45 : 0.55),
        ),
      ),
      // Die Familie muss auch hier stehen — ein Stil in einem Theme-Feld
      // ersetzt den aufgelösten Stil, er ergänzt ihn nicht.
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: Schrift.familie,
          fontSize: Schrift.label,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? text
              : text.withValues(alpha: dark ? 0.45 : 0.55),
        ),
      ),
    ),
    // Ausgewählte Chips in **Markengrün**, nicht in der abgeleiteten
    // `secondaryContainer`-Farbe: aus dem grünen Seed macht Material daraus
    // ein stumpfes Oliv. `SegmentedButton` kommt in der App nicht mehr vor —
    // wo eine Umschaltung nötig ist, steht `PillSelector` bzw. `OptionTile`.
    chipTheme: ChipThemeData(
      selectedColor: MatchUpColors.green,
      checkmarkColor: MatchUpColors.base,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: scheme.outlineVariant),
      // **Die Familie muss hier stehen.** Ein Stil in einem Theme-Feld ersetzt
      // den aufgelösten Stil, er ergänzt ihn nicht — ohne `fontFamily` stand
      // jeder Material-Chip in der Systemschrift, mitten in einer App aus
      // Inter. Dritter Fall derselben Falle nach den
      // Fantasy-Einstellungen und den Reitern.
      labelStyle: const TextStyle(
          fontFamily: Schrift.familie,
          fontWeight: FontWeight.w600,
          fontSize: Schrift.text),
      secondaryLabelStyle: const TextStyle(
          fontFamily: Schrift.familie,
          color: MatchUpColors.base,
          fontWeight: FontWeight.w700,
          fontSize: Schrift.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? MatchUpColors.base : MatchUpColors._lightBg,
      contentPadding: EdgeInsets.zero,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}
