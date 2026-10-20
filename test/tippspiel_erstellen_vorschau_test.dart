import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/tippspiel/ui/create_tip_round.dart';

import 'support/schrift.dart';

/// Vorschau „Tippspiel erstellen":
///   flutter test --update-goldens test/tippspiel_erstellen_vorschau_test.dart
///   -> test/goldens/tippspiel_erstellen.png (Grundzustand)
///   -> test/goldens/tippspiel_erstellen_modi.png (Quoten-Bonus und
///      Bonustipps an, damit die Untereinstellungen im Bild stehen)
///
/// Seit dem 18.10.2026 dieselbe Zeilenform wie „Fantasy-Liga erstellen".
/// Das Bild trägt kein Datum, der Vergleich läuft fest mit.
void main() {
  setUpAll(ladeSchrift);

  Future<void> baue(WidgetTester tester, {double hoehe = 1500}) async {
    tester.view.physicalSize = Size(402 * 3, hoehe * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const CreateTipRoundScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Vorschau: Tippspiel erstellen', (tester) async {
    await baue(tester);
    expect(tester.takeException(), isNull);
    // Die Erklärsätze und die gerahmten Modus-Kacheln sind weg.
    expect(find.textContaining('Frei kombinierbar'), findsNothing);
    expect(find.textContaining('Strafpunkte für einen'), findsNothing);
    expect(find.text('Quoten-Bonus'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
    await expectLater(find.byType(CreateTipRoundScreen),
        matchesGoldenFile('goldens/tippspiel_erstellen.png'));
  });

  testWidgets('Vorschau: Modi mit Untereinstellungen', (tester) async {
    await baue(tester, hoehe: 2300);
    await tester.tap(find.text('Quoten-Bonus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bonustipps'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Außenseiter ab Quote'), findsOneWidget);
    expect(find.text('Punkte je Bonustipp'), findsOneWidget);
    await expectLater(find.byType(CreateTipRoundScreen),
        matchesGoldenFile('goldens/tippspiel_erstellen_modi.png'));
  });
}
