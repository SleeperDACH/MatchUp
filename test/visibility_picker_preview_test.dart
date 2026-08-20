import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/leagues/ui/visibility_picker.dart';

// Vorschau der Sichtbarkeits-Auswahl (kein Regressionstest):
//   flutter test --update-goldens test/visibility_picker_preview_test.dart
// -> test/goldens/visibility_<zustand>.png
void main() {
  testWidgets('Vorschau: Sichtbarkeit privat und öffentlich', (tester) async {
    for (final (name, sicht, modus) in const [
      ('privat', 'private', 'open'),
      ('oeffentlich', 'public', 'invite'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: MatchUpColors.base,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: VisibilityPicker(
                  visibility: sicht,
                  joinPolicy: modus,
                  onChanged: (_, _) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(find.byType(VisibilityPicker),
          matchesGoldenFile('goldens/visibility_$name.png'));
    }
  });
}
