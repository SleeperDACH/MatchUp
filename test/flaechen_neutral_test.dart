import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';

/// **Keine Fläche der App darf grün gestochen sein.**
///
/// `ColorScheme.fromSeed` mischt die Seed-Farbe in jede
/// `surfaceContainer*`-Stufe. Überschrieben war lange nur
/// `surfaceContainerHighest`; die übrigen kamen grün heraus, und weil
/// `showModalBottomSheet` in Material 3 `surfaceContainerLow` nimmt, lag das
/// halbe Spielerprofil auf einer grünen Fläche.
///
/// Der Test prüft nicht einzelne Werte, sondern die **Eigenschaft**: Der
/// Grünkanal darf auf keiner Fläche der stärkste sein. Damit fällt auch eine
/// künftige Stufe auf, die jemand zu überschreiben vergisst.
void main() {
  test('keine Flächenfarbe ist grün gestochen', () {
    for (final helligkeit in [Brightness.dark, Brightness.light]) {
      final s = buildAppTheme(brightness: helligkeit).colorScheme;
      final flaechen = {
        'surface': s.surface,
        'surfaceContainerLowest': s.surfaceContainerLowest,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHigh': s.surfaceContainerHigh,
        'surfaceContainerHighest': s.surfaceContainerHighest,
        'surfaceDim': s.surfaceDim,
        'surfaceBright': s.surfaceBright,
      };
      flaechen.forEach((name, c) {
        expect(c.g > c.r && c.g > c.b, isFalse,
            reason: '$name ist bei $helligkeit grün gestochen '
                '(r=${c.r}, g=${c.g}, b=${c.b})');
      });
    }
  });
}
