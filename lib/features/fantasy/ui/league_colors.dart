import 'package:flutter/material.dart';

import '../models/fantasy_models.dart';

/// Farbfamilien der Liga-Karten. Jede Liga soll ihre eigene Farbe haben —
/// aber man muss auf einen Blick sehen, ob es eine Redraft- oder eine
/// Dynasty-Liga ist. Deshalb nicht eine Palette für alle, sondern zwei
/// getrennte: Redraft kühl (blau/grün), Dynasty warm (magenta/orange).
/// Kein Ton kommt in beiden vor, sonst wäre die Trennung wertlos.
const List<Color> kRedraftPalette = [
  Color(0xFF2E7DF6), // Blau
  Color(0xFF0FC5A6), // Türkis
  Color(0xFF22C55E), // Grün
  Color(0xFF12A9F0), // Himmel
  Color(0xFF4F46E5), // Indigo
  Color(0xFF00B3A4), // Petrol
];

const List<Color> kDynastyPalette = [
  Color(0xFFFF4FA3), // Pink
  Color(0xFFFF6A1A), // Orange
  Color(0xFFF5A310), // Bernstein
  Color(0xFF9B2BFF), // Lila
  Color(0xFFFF3D77), // Rosé
  Color(0xFFF51D1D), // Rot
];

/// Feste Farbe einer Liga: aus dem [seed] (Liga-ID) gewürfelt, aber immer
/// aus der Palette ihres Modus. Derselbe FNV-1a-Hash wie beim Avatar, damit
/// eine Liga ihre Farbe behält, solange ihre ID gleich bleibt.
Color leagueColor(String seed, FantasyMode mode) {
  final palette =
      mode == FantasyMode.dynasty ? kDynastyPalette : kRedraftPalette;
  var h = 0x811c9dc5;
  for (final u in seed.codeUnits) {
    h ^= u;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return palette[h % palette.length];
}
