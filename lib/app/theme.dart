import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      backgroundColor: bg,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

/// Gewählter Theme-Modus (Hell/Dunkel/System) — lokal je Gerät gespeichert.
/// Standard: Dunkel (die App ist dark-first gestaltet).
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s != null) {
      state = ThemeMode.values.firstWhere((m) => m.name == s,
          orElse: () => ThemeMode.dark);
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
