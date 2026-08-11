import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/pill_selector.dart';

// Vorschau des Liga-Umschalters und der „Alle"-Pille im Transfer-Tab
// (kein Regressionstest):
//   flutter test --update-goldens test/pill_preview_test.dart
// -> test/goldens/pill_preview.png

void main() {
  testWidgets('Vorschau: Liga-Umschalter und Filter-Pille', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          backgroundColor: MatchUpColors.base,
          body: Center(
            child: SizedBox(
              width: 402,
              child: RepaintBoundary(
                key: const Key('preview'),
                child: Container(
                  color: MatchUpColors.base,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PillSelector<int>(
                        options: const {
                          1: '1. Bundesliga',
                          2: '2. Bundesliga'
                        },
                        value: 1,
                        onSelect: (_) {},
                      ),
                      const SizedBox(height: 12),
                      // Filterzeile: „Alle" aktiv, daneben inaktiv.
                      Row(
                        children: [
                          PillChip(
                              label: 'Alle',
                              selected: true,
                              onTap: () {}),
                          const SizedBox(width: 8),
                          PillChip(
                              label: 'Alle',
                              selected: false,
                              onTap: () {}),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/pill_preview.png'));
  });
}
