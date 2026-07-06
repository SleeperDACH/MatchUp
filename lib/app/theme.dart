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
}

/// Dunkles MatchUp-Theme: Base als Hintergrund, Green als Akzent, Red als
/// Signalfarbe, Snow als Text. Bewusst nur Dark (kein Light-Theme).
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MatchUpColors.green,
    brightness: Brightness.dark,
  ).copyWith(
    primary: MatchUpColors.green,
    onPrimary: MatchUpColors.base,
    surface: MatchUpColors.base,
    onSurface: MatchUpColors.snow,
    onSurfaceVariant: MatchUpColors._mutedText,
    surfaceContainerHighest: MatchUpColors._surfaceHigh,
    error: MatchUpColors.red,
    onError: MatchUpColors.snow,
    outlineVariant: MatchUpColors._divider,
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'BarlowCondensed',
    scaffoldBackgroundColor: MatchUpColors.base,
    dividerColor: MatchUpColors._divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: MatchUpColors.base,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: MatchUpColors._surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MatchUpColors._surfaceCard,
      indicatorColor: MatchUpColors.green.withValues(alpha: 0.22),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MatchUpColors.base,
      contentPadding: EdgeInsets.zero,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}
