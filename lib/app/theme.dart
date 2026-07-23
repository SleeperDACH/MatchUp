import 'package:flutter/material.dart';

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
    surfaceContainerHighest:
        dark ? MatchUpColors._surfaceHigh : MatchUpColors._lightHigh,
    error: MatchUpColors.red,
    onError: dark ? MatchUpColors.snow : Colors.white,
    outlineVariant: dark ? MatchUpColors._divider : MatchUpColors._lightDivider,
  );

  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'BarlowCondensed',
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
        fontSize: 24,
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
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      indicatorColor: MatchUpColors.green.withValues(alpha: 0.22),
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
