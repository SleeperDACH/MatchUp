import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/create_fantasy_league.dart';
import 'package:matchup/features/fantasy/ui/kader_limits_editor.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau des Schirms **„Fantasy-Liga erstellen"** — wegen der Kader-Limits,
/// die dort neu dazugekommen sind.
///
/// Sie waren vorher nur in den Einstellungen einer **bestehenden** Liga
/// erreichbar; wer beim Anlegen etwas festlegen wollte, musste die Liga erst
/// erzeugen und dann nachbessern.
void main() {
  setUpAll(ladeSchrift);

  Widget rahmen() => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'ich',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const CreateFantasyLeagueScreen(mode: FantasyMode.liga),
        ),
      );

  Future<void> takt(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('Vorschau: Liga erstellen in vier Schritten', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen());
    await takt(tester);

    // **Schritt 1: Name und Teams** — und man sieht, wo man steht.
    expect(find.text('Schritt 1 von 4'), findsOneWidget);
    expect(find.text('LIGA'), findsOneWidget);
    expect(find.text('Zurück'), findsNothing);
    // Das Namensfeld ist ein beschriftetes Feld, kein grauer Beispieltext.
    expect(find.text('Name der Liga'), findsOneWidget);
    expect(find.textContaining('z. B.'), findsNothing);
    await expectLater(find.byType(CreateFantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_erstellen_1.png'));

    // Ohne Namen geht es nicht weiter — mit Grund.
    await tester.tap(find.text('Weiter'));
    await takt(tester);
    expect(find.text('Schritt 1 von 4'), findsOneWidget);
    expect(find.textContaining('mind. 3 Zeichen'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Büro-Liga');
    await tester.tap(find.text('Weiter'));
    await takt(tester);

    // **Schritt 2: Draft** samt Kader-Limits — im Grundzustand nichts
    // begrenzt.
    expect(find.text('Schritt 2 von 4'), findsOneWidget);
    expect(find.text('Zeit je Pick'), findsOneWidget);
    expect(find.text('Runden'), findsOneWidget);
    // Vier Positionen plus Vereins-Limit, alle offen.
    expect(find.text('ohne Limit'), findsNWidgets(5));
    expect(find.text('Spieler je Verein'), findsOneWidget);
    await expectLater(find.byType(CreateFantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_erstellen_2.png'));

    // Zurück führt auf Schritt 1, der Name ist noch da.
    await tester.tap(find.text('Zurück'));
    await takt(tester);
    expect(find.text('Schritt 1 von 4'), findsOneWidget);
    expect(find.text('Büro-Liga'), findsOneWidget);

    await tester.tap(find.text('Weiter'));
    await takt(tester);
    await tester.tap(find.text('Weiter'));
    await takt(tester);

    // **Schritt 3: Saison** — Unentschieden, Playoffs, Winterpause.
    expect(find.text('Schritt 3 von 4'), findsOneWidget);
    expect(find.text('Playoff-Teams'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    await expectLater(find.byType(CreateFantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_erstellen_3.png'));

    await tester.tap(find.text('Weiter'));
    await takt(tester);

    // **Schritt 4: Mitspieler**, und erst hier steht „Liga erstellen".
    expect(find.text('Schritt 4 von 4'), findsOneWidget);
    expect(find.text('Ligainternes Tippspiel'), findsOneWidget);
    expect(find.text('Liga erstellen'), findsOneWidget);
    expect(find.text('Weiter'), findsNothing);
    // Tippspiel einschalten: Die Konfiguration steht sofort darunter.
    expect(find.text('Exaktes Ergebnis'), findsNothing);
    await tester.tap(find.text('Ligainternes Tippspiel'));
    await takt(tester);
    expect(find.text('WETTBEWERBE'), findsOneWidget);
    expect(find.text('Exaktes Ergebnis'), findsOneWidget);
    expect(find.text('Quoten-Bonus'), findsOneWidget);
    await expectLater(find.byType(CreateFantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_erstellen_4.png'));

    // Ein Tipp auf das erste Segment springt zurück zum Anfang.
    await tester.tap(find.bySemanticsLabel('Schritt 1: Liga'));
    await takt(tester);
    expect(find.text('Schritt 1 von 4'), findsOneWidget);
  });

  testWidgets('Kader-Limits begrenzen einzeln, der Rest bleibt offen',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
    tester.view.physicalSize = const Size(402 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen());
    await takt(tester);
    await tester.enterText(find.byType(TextField), 'Büro-Liga');
    await tester.tap(find.text('Weiter'));
    await takt(tester);
    await tester.tap(find.text('ohne Limit').first);
    await takt(tester);
    expect(find.text('ohne Limit'), findsNWidgets(4),
        reason: 'Die offenen Positionen müssen erkennbar bleiben');
  });

  test('die Summenregel gilt erst, wenn alle vier gedeckelt sind', () {
    const r = RosterConfig.standard;
    // Drei gesetzt, eine offen: Die offene nimmt jede Restmenge auf.
    expect(
        KaderLimitsEditor.reichtFuerKader(r, {
          PlayerPosition.gk: 2,
          PlayerPosition.def: 2,
          PlayerPosition.mid: 2,
          PlayerPosition.fwd: null,
        }),
        isTrue);
    // Alle vier gesetzt, zusammen zu wenig für den Kader.
    expect(
        KaderLimitsEditor.reichtFuerKader(r, {
          PlayerPosition.gk: 2,
          PlayerPosition.def: 2,
          PlayerPosition.mid: 2,
          PlayerPosition.fwd: 2,
        }),
        isFalse);
  });
}
