import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/farben.dart';
import 'package:matchup/app/theme.dart';

/// Kontrastverhältnis nach WCAG 2.x.
double kontrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final hell = buildAppTheme(brightness: Brightness.light);
  final dunkel = buildAppTheme(brightness: Brightness.dark);
  final s = hell.colorScheme;

  // **Was als Schrift oder Zeichen auf Weiß steht, muss lesbar sein.** Die
  // Signalfarben des dunklen Modus lagen auf Weiß bei 1,6:1 (Gold) und 1,8:1
  // (Grün) — genau das soll nicht zurückkommen.
  final signale = <String, Color>{
    'gruen': MatchUpFarben.hell.gruen,
    'rot': MatchUpFarben.hell.rot,
    'gold': MatchUpFarben.hell.gold,
    'blau': MatchUpFarben.hell.blau,
    'tuerkis': MatchUpFarben.hell.tuerkis,
    'orange': MatchUpFarben.hell.orange,
    'violett': MatchUpFarben.hell.violett,
    'silber': MatchUpFarben.hell.silber,
    'bronze': MatchUpFarben.hell.bronze,
    'neutral': MatchUpFarben.hell.neutral,
  };

  test('der Grund ist reines Weiß', () {
    expect(hell.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    expect(s.surface, const Color(0xFFFFFFFF));
  });

  test('Signalfarben sind auf Weiß lesbar (≥ 4,5:1)', () {
    for (final e in signale.entries) {
      expect(kontrast(e.value, s.surface), greaterThanOrEqualTo(4.5),
          reason: '${e.key} auf Weiß');
    }
  });

  test('Signalfarben sind auf Karten lesbar (≥ 4:1)', () {
    for (final e in signale.entries) {
      expect(kontrast(e.value, s.surfaceContainer), greaterThanOrEqualTo(4.0),
          reason: '${e.key} auf der Kartenfläche');
    }
  });

  test('Schrift und Sekundärschrift auf Weiß und auf Karten', () {
    for (final grund in [s.surface, s.surfaceContainer]) {
      expect(kontrast(s.onSurface, grund), greaterThanOrEqualTo(7));
      expect(kontrast(s.onSurfaceVariant, grund), greaterThanOrEqualTo(4.5));
      expect(kontrast(s.primary, grund), greaterThanOrEqualTo(4.0));
      expect(kontrast(s.error, grund), greaterThanOrEqualTo(4.5));
    }
  });

  test('Karten heben sich vom weißen Grund ab, Haarlinie ist sichtbar', () {
    expect(s.surfaceContainer, isNot(s.surface));
    expect(kontrast(s.outlineVariant, s.surface), greaterThan(1.3));
  });

  test('gefüllter Hauptknopf: dunkel auf Hell, hell auf Dunkel', () {
    final knopf = hell.filledButtonTheme.style!;
    final bg = knopf.backgroundColor!.resolve({})!;
    final fg = knopf.foregroundColor!.resolve({})!;
    expect(kontrast(bg, fg), greaterThanOrEqualTo(7));
    expect(kontrast(bg, s.surface), greaterThanOrEqualTo(7),
        reason: 'der Knopf muss sich vom weißen Grund abheben');
  });

  test('der dunkle Modus bleibt, wie er war', () {
    // Die Werte von vor dem hellen Modus — er darf sich um keinen Pixel
    // ändern.
    expect(dunkel.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(dunkel.colorScheme.primary, const Color(0xFF4ADE6A));
    expect(dunkel.colorScheme.error, const Color(0xFFF23030));
    expect(dunkel.colorScheme.onSurface, MatchUpColors.snow);
    expect(MatchUpFarben.dunkel.gold, const Color(0xFFFFC83D));
    expect(MatchUpFarben.dunkel.gruen, MatchUpColors.green);
    expect(MatchUpFarben.dunkel.rot, MatchUpColors.red);
    expect(dunkel.extension<MatchUpFarben>(), MatchUpFarben.dunkel);
    expect(hell.extension<MatchUpFarben>(), MatchUpFarben.hell);
  });
}
