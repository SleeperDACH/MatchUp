import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/ui/app_avatar.dart';
import 'package:matchup/core/ui/eingabe_blatt.dart';

import 'support/schrift.dart';

/// Das **Eingabe-Blatt** ersetzt die letzten sechs `AlertDialog`s
/// (20.10.2026). Vorschau plus das Verhalten, das die Kästen vorher hatten:
/// Fehler lassen das Blatt offen, Abbrechen liefert `null`.
///   flutter test --update-goldens test/eingabe_blatt_test.dart
void main() {
  setUpAll(ladeSchrift);

  Future<void> baue(WidgetTester tester, Widget kind) async {
    tester.view.physicalSize = const Size(402 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(body: kind),
    ));
  }

  testWidgets('Vorschau: Passwort ändern mit Fehler', (tester) async {
    await baue(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: EingabeBlatt(
          titel: 'Passwort ändern',
          felder: const [
            EingabeFeld(label: 'Aktuelles Passwort', verdeckt: true),
            EingabeFeld(label: 'Neues Passwort', verdeckt: true),
            EingabeFeld(label: 'Neues Passwort bestätigen', verdeckt: true),
          ],
          ja: 'Speichern',
          pruefe: (w) => 'Bitte alle Felder ausfüllen.',
        ),
      ),
    );
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(find.text('Bitte alle Felder ausfüllen.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/eingabe_blatt.png'));
  });

  testWidgets('Fehler lässt offen, gültige Eingabe kommt zurück',
      (tester) async {
    String? ergebnis = 'unberührt';
    await baue(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            ergebnis = await eingabe(
              context,
              titel: 'Liga-Name ändern',
              feld: const EingabeFeld(label: 'Name der Liga', start: 'ab'),
              ja: 'Speichern',
              pruefe: (v) => v.length < 3 ? 'Zu kurz' : null,
            );
          },
          child: const Text('öffnen'),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Zu kurz'), findsOneWidget);
    expect(ergebnis, 'unberührt');

    await tester.enterText(find.byType(TextField), '  Bundesliga  ');
    await tester.pump();
    expect(find.text('Zu kurz'), findsNothing);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(ergebnis, 'Bundesliga');
    expect(find.byType(EingabeBlatt), findsNothing);
  });

  testWidgets('Abbrechen liefert null', (tester) async {
    List<String>? ergebnis = const ['unberührt'];
    await baue(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            ergebnis = await eingabeBlatt(
              context,
              titel: 'Beitreten',
              felder: const [EingabeFeld(label: 'Einladungscode')],
              ja: 'Beitreten',
            );
          },
          child: const Text('öffnen'),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(ergebnis, isNull);
  });

  test('alsEmoji erzwingt Emoji-Darstellung nur, wo nötig', () {
    expect(alsEmoji('⚽'), '⚽️');
    expect(alsEmoji('⚡'), '⚡️');
    // Schon bunte Emojis und solche mit Selektor bleiben, wie sie sind.
    expect(alsEmoji('🏆'), '🏆');
    expect(alsEmoji('🛡️'), '🛡️');
  });
}
