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

  testWidgets('Vorschau: Liga erstellen mit Kader-Limits', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 1500 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Der Abschnitt ist da, und im Grundzustand ist nichts begrenzt — eine
    // stillschweigend eingeführte Obergrenze wäre eine Regel, die niemand
    // gewählt hat.
    expect(find.text('KADER-LIMITS'), findsOneWidget);
    expect(find.text('Keine Position ist begrenzt — es gilt keine Obergrenze.'),
        findsOneWidget);

    await expectLater(find.byType(CreateFantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_erstellen_limits_aus.png'));

    // Torhüter begrenzen: Der Vorschlag beim Einschalten ist die
    // Startelf-Obergrenze plus eine Reserve.
    await tester.tap(find.text('ohne Limit').first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
        find.textContaining('Ohne Limit: Abwehr, Mittelfeld, Sturm'),
        findsOneWidget,
        reason: 'Die offenen Positionen müssen benannt werden');

    await expectLater(find.byType(CreateFantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_erstellen_limits_teilweise.png'));
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
