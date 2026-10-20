import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/push/push_einstellungen.dart';
import 'package:matchup/features/push/ui/push_einstellungen_screen.dart';

import 'support/schrift.dart';

/// Vorschau der **Benachrichtigungs-Einstellungen**:
///   flutter test --update-goldens test/push_einstellungen_vorschau_test.dart
///   -> test/goldens/push_einstellungen.png (Übersicht der Bereiche)
///   -> test/goldens/push_bereich_live.png (die Schalter eines Bereichs)
///
/// Seit dem 18.10.2026 zwei Ebenen: Die Übersicht zeigt je Bereich eine
/// Zeile mit dem Stand, ein Tipp öffnet die Schalter. Zwei Schalter sind aus,
/// damit „N von M an" im Bild steht und an/aus auf dem Bereichsschirm.
///
/// Das Bild trägt kein Datum, der Vergleich läuft deshalb fest mit.
void main() {
  setUpAll(ladeSchrift);

  final stand = const PushEinstellungen.allesAn()
      .kopieMit('liga_chat', false)
      .kopieMit('live_halbzeit', false);

  Future<void> baue(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
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
  }

  testWidgets('Vorschau: Übersicht mit vier Bereichen', (tester) async {
    await baue(tester);

    // Jeder Bereich ist eine Zeile — keine Schalter auf der Übersicht.
    for (final b in PushBereich.values) {
      expect(find.text(b.titel), findsOneWidget, reason: b.titel);
    }
    expect(find.byType(SwitchListTile), findsNothing);
    // Der Stand je Bereich: einer ist teilweise aus, die anderen ganz an.
    final live = PushKategorie.imBereich(PushBereich.live).length;
    expect(find.text('${live - 1} von $live an'), findsOneWidget);
    // Die beiden Sammelsorten aus 0129 sind weg.
    expect(find.text('Nachrichten'), findsNothing);
    expect(find.text('Anfragen'), findsNothing);

    await expectLater(
      find.byType(PushEinstellungenScreen),
      matchesGoldenFile('goldens/push_einstellungen.png'),
    );
  });

  testWidgets('Ein Bereich öffnet seine Schalter, und nur seine',
      (tester) async {
    await baue(tester);
    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();

    expect(find.byType(PushBereichScreen), findsOneWidget);
    expect(find.byType(SwitchListTile),
        findsNWidgets(PushKategorie.imBereich(PushBereich.live).length));
    // Darüber der Weg zu Vereinen und Ligen ohne Favorit (0142).
    expect(find.text('Vereine & Ligen'), findsOneWidget);
    expect(find.text('Nur Favoriten'), findsOneWidget);

    await expectLater(
      find.byType(PushBereichScreen),
      matchesGoldenFile('goldens/push_bereich_live.png'),
    );
  });

  test('Jede Sorte gehört zu genau einem Bereich', () {
    final summe = PushBereich.values
        .map((b) => PushKategorie.imBereich(b).length)
        .fold(0, (a, b) => a + b);
    expect(summe, PushKategorie.alle.length);
  });
}
