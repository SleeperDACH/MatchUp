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

  Future<void> baue(WidgetTester tester, {double hoehe = 874}) async {
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

  testWidgets('Vorschau: Tippspiel erstellen in drei Schritten',
      (tester) async {
    await baue(tester);
    expect(find.text('Schritt 1 von 3'), findsOneWidget);
    expect(find.text('Quoten-Bonus'), findsNothing);
    await expectLater(find.byType(CreateTipRoundScreen),
        matchesGoldenFile('goldens/tippspiel_erstellen_1.png'));

    await tester.enterText(find.byType(TextField), 'Büro-Tippspiel');
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 2 von 3'), findsOneWidget);
    expect(find.text('Exaktes Ergebnis'), findsOneWidget);
    expect(find.text('Quoten-Bonus'), findsNothing);
    await expectLater(find.byType(CreateTipRoundScreen),
        matchesGoldenFile('goldens/tippspiel_erstellen_2.png'));

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 3 von 3'), findsOneWidget);
    expect(find.text('Quoten-Bonus'), findsOneWidget);
    expect(find.text('Öffentlich'), findsOneWidget);
    expect(find.text('Tipprunde erstellen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(CreateTipRoundScreen),
        matchesGoldenFile('goldens/tippspiel_erstellen_3.png'));
  });

  testWidgets('Punkte und Modi auf zwei Seiten überschreiben sich nicht',
      (tester) async {
    await baue(tester, hoehe: 1600);
    await tester.enterText(find.byType(TextField), 'Büro-Tippspiel');
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    // Exakt von 4 auf 5.
    await tester.tap(find.byTooltip('Exaktes Ergebnis erhöhen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quoten-Bonus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bonustipps'));
    await tester.pumpAndSettle();
    expect(find.text('Außenseiter ab Quote'), findsOneWidget);
    expect(find.text('Punkte je Bonustipp'), findsOneWidget);
    // Zurück auf die Punkte: die 5 steht noch.
    await tester.tap(find.text('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Außenseiter ab Quote'), findsOneWidget);
    await expectLater(find.byType(CreateTipRoundScreen),
        matchesGoldenFile('goldens/tippspiel_erstellen_modi.png'));
  });
}
