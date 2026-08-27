import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/fantasy/ui/scoring_info_screen.dart';

import 'support/schrift.dart';

/// Vorschau der **Punktevergabe** — kein Regressionstest:
///   flutter test --update-goldens test/punktevergabe_vorschau_test.dart
///
/// Zwei Bilder, weil der Schirm genau davon lebt: Der Torwart sieht Paraden,
/// Zu Null und Gegentore, der Stürmer keins davon — dafür eine niedrigere
/// Schwelle für den Defensivbonus. Ein Bild allein zeigte das nicht.
void main() {
  setUpAll(ladeSchrift);

  Future<void> bauen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1300 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const ScoringInfoScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Vorschau: Punktevergabe — Torwart', (tester) async {
    await bauen(tester);
    await expectLater(
      find.byType(ScoringInfoScreen),
      matchesGoldenFile('goldens/punktevergabe_torwart.png'),
    );
  });

  testWidgets('Vorschau: Punktevergabe — Sturm', (tester) async {
    await bauen(tester);
    await tester.tap(find.text('Sturm'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ScoringInfoScreen),
      matchesGoldenFile('goldens/punktevergabe_sturm.png'),
    );
  });
}
