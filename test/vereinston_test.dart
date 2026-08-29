import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_screen.dart';
import 'package:matchup/app/theme.dart';

/// **Jeder Verein muss auf der Kopfkarte eine sichtbare Farbe bekommen.**
///
/// Anlass: Bei Dortmund fehlte der Hof am Wappen und die Tönung an der Seite
/// vollständig. `vereinsTon` gab dort `#15171E` zurück — praktisch die
/// Hintergrundfarbe der App. Die alte Regel prüfte die **Helligkeit** der
/// Grundfarbe und trat bei „zu hell" an `secondary` ab, ohne zu prüfen, ob die
/// etwas taugt: Dortmunds Gelb ist zu hell, also Schwarz. Eine Farbe kam
/// zurück, sichtbar war nichts.
///
/// Auf dem Gerät sieht man immer nur die zwei Vereine, die gerade spielen —
/// deshalb steht hier die vollständige Liste. Es sind die Vereinsnamen, wie
/// sie in `fixtures` stehen (beide Schreibweisen, die dort vorkommen).
void main() {
  const vereine = [
    '1. FC Köln',
    '1. FC Union Berlin',
    '1. FSV Mainz 05',
    'Bayer 04 Leverkusen',
    'Borussia Dortmund',
    'Borussia Mönchengladbach',
    'Eintracht Frankfurt',
    'Elversberg',
    'FC Augsburg',
    'FC Bayern München',
    'FC Köln',
    'FC Schalke 04',
    'FC Union Berlin',
    'FSV Mainz 05',
    'Hamburger SV',
    'Paderborn',
    'RB Leipzig',
    'SC Freiburg',
    'SC Paderborn 07',
    'Schalke 04',
    'SV 07 Elversberg',
    'SV Werder Bremen',
    'TSG Hoffenheim',
    'VfB Stuttgart',
    'Werder Bremen',
  ];

  /// Die Buntheit — Abstand zwischen stärkstem und schwächstem Kanal.
  double buntheit(Color c) {
    final k = [c.r, c.g, c.b];
    return k.reduce(math.max) - k.reduce(math.min);
  }

  test('jeder Bundesliga-Verein bekommt einen Ton', () {
    final ohne = vereine.where((v) => vereinsTon(v) == null).toList();
    expect(ohne, isEmpty, reason: 'ohne Vereinsfarbe: $ohne');
  });

  test('kein Ton ist Grau, Weiß oder Schwarz', () {
    // Genau das war der Fehler: Dortmund bekam Schwarz, und fünf Vereine mit
    // weißem Trikot bekamen denselben blaugrauen Ton, weil die HSL-Sättigung
    // bei fast-Weiß nicht aussagekräftig ist.
    for (final v in vereine) {
      final ton = vereinsTon(v)!;
      expect(buntheit(ton), greaterThanOrEqualTo(0.20),
          reason: '$v bekommt einen unbunten Ton');
    }
  });

  test('jeder Ton hebt sich vom fast schwarzen Grund ab', () {
    // Der Hof am Wappen liegt mit 62 % Deckung auf dem Kartengrund. Was sich
    // dort nicht abhebt, ist auf dem Schirm schlicht nicht da — unabhängig
    // davon, ob eine Farbe zurückkam.
    const grund = MatchUpColors.base;
    for (final v in vereine) {
      final hof = Color.alphaBlend(vereinsTon(v)!.withValues(alpha: 0.62), grund);
      final abstand =
          (hof.computeLuminance() - grund.computeLuminance()).abs();
      expect(abstand, greaterThan(0.02),
          reason: '$v verschwindet im Hintergrund');
    }
  });

  test('ein unbekannter Verein bekommt keine erfundene Farbe', () {
    // Ein Pokalgegner aus der Oberliga: eine erfundene Farbe sähe aus wie
    // eine Auskunft.
    expect(vereinsTon('SV Blau-Weiß Irgendwo'), isNull);
  });
}
