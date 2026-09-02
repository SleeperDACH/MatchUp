import 'package:flutter/material.dart';

import 'typografie.dart';

/// MatchUp-Markenfarben.
class MatchUpColors {
  const MatchUpColors._();

  /// Dunkler Hintergrund (fast Schwarz mit leichtem Blaustich).
  static const base = Color(0xFF12141C);

  /// Marken-/Primärakzent (Logo-„Up", Buttons, aktive Zustände).
  static const green = Color(0xFF4ADE6A);

  /// Signalfarbe: Fehler/Negativ und Live-Spiele.
  static const red = Color(0xFFF23030);

  /// Text/Vordergrund auf dunklem Grund.
  static const snow = Color(0xFFEDEFF4);

  // Abgestufte Flächen über [base] für Tiefe (Karten, Leisten, Kopfzeilen).
  static const _surfaceCard = Color(0xFF1A1D27);
  static const _surfaceHigh = Color(0xFF252937);
  // Die übrigen Stufen der Material-3-Flächenleiter, **neutral gehalten**.
  // Siehe die Erklärung am Farbschema: Ohne sie mischt Material 3 die grüne
  // Seed-Farbe hinein.
  static const _surfaceLowest = Color(0xFF0E1016);
  static const _surfaceLow = Color(0xFF161822);
  static const _surfaceMid = Color(0xFF1F2330);
  static const _divider = Color(0xFF2A2E3A);

  /// Gedämpftes Snow für Sekundärtext.
  static const _mutedText = Color(0xFFA6ACBA);

  // Helle Variante (Light-Theme): heller Grund, dunkle Schrift, gleiche Akzente.
  static const _lightBg = Color(0xFFF5F6F8);
  static const _lightCard = Colors.white;
  static const _lightHigh = Color(0xFFE8EAF0);
  static const _lightDivider = Color(0xFFE1E3EA);
  static const _lightMuted = Color(0xFF5F636E);
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
  final glassBorder = Colors.white.withValues(alpha: dark ? 0.10 : 0.55);

  final scheme = ColorScheme.fromSeed(
    seedColor: MatchUpColors.green,
    brightness: brightness,
  ).copyWith(
    primary: MatchUpColors.green,
    onPrimary: MatchUpColors.base,
    surface: bg,
    onSurface: dark ? MatchUpColors.snow : MatchUpColors.base,
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
        dark ? MatchUpColors._surfaceLowest : MatchUpColors._lightCard,
    surfaceContainerLow:
        dark ? MatchUpColors._surfaceLow : MatchUpColors._lightCard,
    surfaceContainer:
        dark ? MatchUpColors._surfaceCard : MatchUpColors._lightCard,
    surfaceContainerHigh:
        dark ? MatchUpColors._surfaceMid : MatchUpColors._lightHigh,
    surfaceContainerHighest:
        dark ? MatchUpColors._surfaceHigh : MatchUpColors._lightHigh,
    // `surfaceDim` und `surfaceBright` gehören zur selben Leiter und wurden
    // beim ersten Anlauf übersehen — der Wächtertest hat sie gefunden.
    surfaceDim: dark ? MatchUpColors._surfaceLowest : MatchUpColors._lightHigh,
    surfaceBright: dark ? MatchUpColors._surfaceMid : MatchUpColors._lightCard,
    error: MatchUpColors.red,
    onError: dark ? MatchUpColors.snow : Colors.white,
    outlineVariant: dark ? MatchUpColors._divider : MatchUpColors._lightDivider,
  );

  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'BarlowCondensed',
    // **Eine Schriftskala statt Materials Vorgaben.** Ohne `textTheme` kommen
    // die Größen aus Material (bodyMedium 14, titleLarge 22 …) — eine Leiter,
    // die für eine normale Grotesk gedacht ist, nicht für eine schmale.
    // `Schrift` in `typografie.dart` trägt die Stufen; jeder Stil dort nennt
    // die Familie ausdrücklich, weil ein Theme-Stil den aufgelösten *ersetzt*.
    textTheme: matchUpTextTheme(
        dark ? MatchUpColors.snow : MatchUpColors.base,
        dark ? MatchUpColors._mutedText : MatchUpColors._lightMuted),
    scaffoldBackgroundColor: bg,
    dividerColor: scheme.outlineVariant,
    appBarTheme: AppBarTheme(
      backgroundColor: bg.withValues(alpha: 0.0),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      // Auffälliger, „dicker" Titel in condensed Schrift — überall einheitlich
      // (wie die überarbeitete Liga-Kopfzeile, siehe VibrantLeagueTitle).
      titleTextStyle: TextStyle(
        fontFamily: 'BarlowCondensed',
        fontWeight: FontWeight.w800,
        fontSize: Schrift.h1,
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
        backgroundColor: dark ? MatchUpColors.snow : MatchUpColors.base,
        foregroundColor: dark ? MatchUpColors.base : MatchUpColors.snow,
        disabledBackgroundColor: scheme.surfaceContainerHigh,
        disabledForegroundColor: scheme.onSurfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        // Die Familie muss auch hier stehen — dieselbe Falle wie beim
        // Chip-Stil: Ein Stil in einem Theme-Feld ersetzt den aufgelösten.
        textStyle: const TextStyle(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w800,
          fontSize: Schrift.titel,
          letterSpacing: 0.2,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      indicatorColor: MatchUpColors.green.withValues(alpha: 0.22),
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
      // Barlow Condensed. Dritter Fall derselben Falle nach den
      // Fantasy-Einstellungen und den Reitern.
      labelStyle: const TextStyle(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w600,
          fontSize: Schrift.koerper),
      secondaryLabelStyle: const TextStyle(
          fontFamily: 'BarlowCondensed',
          color: MatchUpColors.base,
          fontWeight: FontWeight.w700,
          fontSize: Schrift.koerper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? MatchUpColors.base : MatchUpColors._lightCard,
      contentPadding: EdgeInsets.zero,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}
