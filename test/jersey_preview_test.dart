import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/widgets/jersey_icon.dart';
import 'package:matchup/core/util/club_colors.dart';

// Vorschau der Trikot-Symbole auf dem Rasen (kein Regressionstest):
//   flutter test --update-goldens test/jersey_preview_test.dart
// -> test/goldens/jersey_preview.png
//
// Bewusst mit den kritischen Fällen bestückt: sehr helle Trikots (Gladbach,
// Bielefeld), sehr dunkle (Frankfurt, Freiburg) und knallige (Dortmund,
// Dresden). Daran zeigt sich, ob Kontur und Nummernfarbe tragen.

const _fallback = ClubColors(Color(0xFF4ADE6A), Color(0xFF0E2C1A));

void main() {
  testWidgets('Vorschau: Trikots in Vereinsfarben mit Rückennummer',
      (tester) async {
    const vereine = <(String, int)>[
      ('FC Bayern München', 9),
      ('Borussia Dortmund', 7),
      ('Borussia Mönchengladbach', 10),
      ('Eintracht Frankfurt', 4),
      ('SC Freiburg', 1),
      ('RB Leipzig', 11),
      ('DSC Arminia Bielefeld', 23),
      ('Dynamo Dresden', 18),
      ('FC St. Pauli', 6),
      ('Unbekannter SV', 2),
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const Key('preview'),
              child: Container(
                width: 420,
                // Rasengrün wie auf dem Spielfeld — nur davor zählt der
                // Kontrast.
                color: const Color(0xFF1F7A3D),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Große Ausgabe: hier ist zu sehen, wo die Nummer sitzt und
                    // ob sie sich vom Stoff abhebt (im Test-Renderer als
                    // Kästchen — hell auf dunklem, dunkel auf hellem Trikot).
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final n in ['Borussia Dortmund',
                                         'Eintracht Frankfurt',
                                         'Borussia Mönchengladbach'])
                          JerseyIcon(
                            colors: clubColors(n, fallback: _fallback),
                            number: 10,
                            size: 84,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: [
                    for (final (name, nummer) in vereine)
                      SizedBox(
                        width: 72,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            JerseyIcon(
                              colors:
                                  clubColors(name, fallback: _fallback),
                              number: nummer,
                              size: 34,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              name.split(' ').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 2)
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/jersey_preview.png'));
  });

  test('Vereinsfarben werden tolerant zugeordnet', () {
    // Dieselbe Mannschaft, drei Schreibweisen aus drei Quellen.
    final a = clubColors('1. FC Nürnberg', fallback: _fallback);
    final b = clubColors('Nürnberg', fallback: _fallback);
    final c = clubColors('Nurnberg', fallback: _fallback);
    expect(a.primary, b.primary);
    expect(b.primary, c.primary);
    expect(a.primary, isNot(_fallback.primary));
  });

  test('Borussia trennt Dortmund und Mönchengladbach', () {
    final bvb = clubColors('Borussia Dortmund', fallback: _fallback);
    final bmg = clubColors('Borussia Mönchengladbach', fallback: _fallback);
    expect(bvb.primary, isNot(bmg.primary));
  });

  test('unbekannter Verein bekommt die Ausweichfarbe', () {
    expect(clubColors('FC Irgendwo', fallback: _fallback).primary,
        _fallback.primary);
  });

  test('Nummernfarbe richtet sich nach der Helligkeit des Trikots', () {
    expect(jerseyTextColor(const Color(0xFFFDE100)).computeLuminance(),
        lessThan(0.2), reason: 'dunkle Schrift auf gelbem Trikot');
    expect(jerseyTextColor(const Color(0xFF15171E)).computeLuminance(),
        greaterThan(0.7), reason: 'helle Schrift auf dunklem Trikot');
  });
}
