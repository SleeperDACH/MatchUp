import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_screen.dart';
import 'package:matchup/app/theme.dart';

import 'support/schrift.dart';

/// Vorschau des Schirms „Neu starten" (Fantasy · Tippspiel · Mit Code
/// beitreten):
///   flutter test --update-goldens test/neu_starten_vorschau_test.dart
///   -> test/goldens/neu_starten.png
///
/// Seit dem 18.10.2026 ohne Überschrift, Erklärsatz und Untertitel; die
/// beiden Karten teilen sich die Höhe. Die Hintergrundbilder erscheinen in
/// Vorschauen nicht (Dekodieren ist echtes I/O) — beurteilt wird die
/// Anordnung. Das Bild trägt kein Datum, der Vergleich läuft fest mit.
void main() {
  setUpAll(ladeSchrift);

  Future<void> oeffne(WidgetTester tester,
      {Size groesse = const Size(402, 874), double schrift = 1}) async {
    tester.view.physicalSize = groesse * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(schrift)),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCreateOrJoin(context, ref),
                child: const Text('öffnen'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets('Vorschau: Neu starten', (tester) async {
    await oeffne(tester);
    expect(find.text('FANTASY'), findsOneWidget);
    expect(find.text('TIPPSPIEL'), findsOneWidget);
    expect(find.text('Mit Code beitreten'), findsOneWidget);
    // Die Untertitel und der Erklärsatz sind weg.
    expect(find.textContaining('draften'), findsNothing);
    expect(find.textContaining('Was möchtest du spielen'), findsNothing);
    await expectLater(find.byType(Scaffold).last,
        matchesGoldenFile('goldens/neu_starten.png'));
  });

  testWidgets('Kleines Gerät, große Schrift: nichts läuft über',
      (tester) async {
    await oeffne(tester, groesse: const Size(375, 667), schrift: 1.6);
    expect(tester.takeException(), isNull);
    expect(find.text('Mit Code beitreten'), findsOneWidget);
  });
}
