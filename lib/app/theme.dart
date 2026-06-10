import 'package:flutter/material.dart';

/// Dunkles Theme im Stil moderner Fantasy-Apps (Sleeper): dunkles Navy
/// mit Türkis als Akzentfarbe.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF00CEB8),
    brightness: Brightness.dark,
    surface: const Color(0xFF151B2B),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0E1320),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0E1320),
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A2236),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF151B2B),
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0E1320),
      contentPadding: EdgeInsets.zero,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}
