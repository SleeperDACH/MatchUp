import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/matchup_splash.dart';

// Vorschau des Startbildschirms in vier Phasen (kein Regressionstest):
//   flutter test --update-goldens test/splash_preview_test.dart
// -> test/goldens/splash_<ms>.png
//
// Die Wortmarke erscheint als Kästchen: Widget-Tests laden die App-Schrift
// nicht. Geprüft wird hier die Bewegung der beiden Markenhälften.
void main() {
  testWidgets('Vorschau: Startbildschirm fährt zusammen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Draußen · halb drin · zusammengetroffen · mit Wortmarke.
    for (final ms in [120, 380, 700, 1150]) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const MatchUpSplash(child: SizedBox.shrink()),
        ),
      );
      await tester.pump(Duration(milliseconds: ms));
      await expectLater(find.byType(MatchUpSplash),
          matchesGoldenFile('goldens/splash_$ms.png'));
      // Frischer Aufbau, damit der nächste Zeitpunkt wieder bei 0 startet.
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
