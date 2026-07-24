import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/ui/default_avatar.dart';

// Erzeugt das Vorschaubild des Standard-Avatars (kein Regressionstest):
//   flutter test --update-goldens test/default_avatar_preview_test.dart
// legt test/goldens/default_avatar_preview.png an.
void main() {
  testWidgets('Vorschau: MatchUp-Gesicht in verschiedenen Farben/Größen',
      (tester) async {
    const names = [
      'Alex', 'Bea', 'Chris', 'Dana', 'Elias', 'Finn', 'Greta', 'Hodor',
      'Ida', 'Jonas', 'Kira', 'Lars', 'Mila', 'Noah', 'Ole', 'Pia',
      'Quin', 'Rosa', 'Sven', 'Tara', 'Uwe', 'Vera', 'Wim', 'Xena',
    ];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF12141C),
          body: Center(
            child: RepaintBoundary(
              key: const Key('preview'),
              child: Container(
                color: const Color(0xFF12141C),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 8 * 56 + 7 * 12,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final n in names)
                            DefaultAvatar(seed: n, size: 56),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        DefaultAvatar(seed: 'Mila', size: 20),
                        SizedBox(width: 14),
                        DefaultAvatar(seed: 'Mila', size: 28),
                        SizedBox(width: 14),
                        DefaultAvatar(seed: 'Mila', size: 40),
                        SizedBox(width: 14),
                        DefaultAvatar(seed: 'Mila', size: 56),
                        SizedBox(width: 14),
                        DefaultAvatar(seed: 'Mila', size: 80),
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
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/default_avatar_preview.png'));
  });
}
