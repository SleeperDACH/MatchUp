import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/push/push_einstellungen.dart';
import 'package:matchup/features/push/ui/push_einstellungen_screen.dart';

import 'support/schrift.dart';

/// Vorschau der **Benachrichtigungs-Einstellungen**:
///   flutter test --update-goldens test/push_einstellungen_vorschau_test.dart
///   -> test/goldens/push_einstellungen.png
///
/// Gezeigt wird der ganze Schirm auf einem hohen Gerät — die vier Bereiche
/// stehen untereinander, und auf Telefonhöhe wäre nur der erste zu sehen.
/// Zwei Schalter sind aus, damit man den Unterschied zwischen an und aus im
/// selben Bild hat.
///
/// Das Bild trägt kein Datum, der Vergleich läuft deshalb fest mit.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Benachrichtigungen in vier Bereichen', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 2300 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final stand = const PushEinstellungen.allesAn()
        .kopieMit('liga_chat', false)
        .kopieMit('live_halbzeit', false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushEinstellungenProvider.overrideWith((ref) async => stand),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const PushEinstellungenScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Jeder Bereich hat seine Überschrift, und jede Sorte steht genau einmal da.
    for (final b in PushBereich.values) {
      expect(find.text(b.titel.toUpperCase()).evaluate().isNotEmpty ||
              find.text(b.titel).evaluate().isNotEmpty,
          isTrue,
          reason: b.titel);
    }
    expect(find.byType(SwitchListTile), findsNWidgets(PushKategorie.alle.length));
    // Die beiden Sammelsorten aus 0129 sind weg.
    expect(find.text('Nachrichten'), findsNothing);
    expect(find.text('Anfragen'), findsNothing);

    await expectLater(
      find.byType(PushEinstellungenScreen),
      matchesGoldenFile('goldens/push_einstellungen.png'),
    );
  });
}
