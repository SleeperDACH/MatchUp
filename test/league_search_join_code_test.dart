import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/leagues/models/public_league_result.dart';
import 'package:matchup/features/leagues/providers.dart';
import 'package:matchup/features/leagues/ui/league_search_screen.dart';

import 'support/schrift.dart';

/// Der Schirm „Ligen entdecken" listet ausschließlich **öffentliche** Ligen.
/// Eine private steht in keinem Suchergebnis, egal wie genau man ihren Namen
/// tippt — der einzige Weg hinein ist der Einladungscode. Genau der fehlte
/// hier: wer eingeladen wurde, musste den Schirm verlassen und das „+" auf dem
/// Homescreen finden. Diese Tests halten den Knopf und seinen Dialog fest.
Widget _screen(List<PublicLeagueResult> treffer) => ProviderScope(
      overrides: [
        // Die ganze Family überschreiben, nicht nur den leeren Suchbegriff:
        // sonst greift beim ersten Tippen wieder das echte Repository — und
        // das fasst `Supabase.instance` an, die es im Test nicht gibt.
        publicLeagueSearchProvider.overrideWith((ref, query) => treffer),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const LeagueSearchScreen(),
      ),
    );

/// Ein öffentlicher Treffer, damit die Liste nicht leer ist.
const _treffer = PublicLeagueResult(
  kind: 'fantasy',
  id: 'l1',
  name: 'Offene Runde',
  season: 2026,
  memberCount: 3,
  joinPolicy: 'open',
  joinable: true,
  isMember: false,
  requested: false,
);

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: „Ligen entdecken" mit dem Knopf', (tester) async {
    tester.view.physicalSize = const Size(1206, 1600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_screen(const [_treffer]));
    await tester.pumpAndSettle();

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/league_search_join_code.png'));
  });

  testWidgets('Der Knopf steht auf dem Schirm, auch wenn es Treffer gibt',
      (tester) async {
    await tester.pumpWidget(_screen(const [_treffer]));
    await tester.pump();

    // Erst der Beleg, dass die Liste wirklich gefüllt ist — sonst prüft der
    // Test den Leerzustand und behauptet das Gegenteil.
    expect(find.text('Offene Runde'), findsOneWidget);
    expect(find.text('Mit Einladungscode beitreten'), findsOneWidget);
  });

  testWidgets('Ein Tipp darauf öffnet die Code-Eingabe', (tester) async {
    await tester.pumpWidget(_screen(const []));
    await tester.pump();

    await tester.tap(find.text('Mit Einladungscode beitreten'));
    await tester.pumpAndSettle();

    // Der Dialog fragt nach dem Code — und sagt, dass er für beide Spielarten
    // gilt; der Code selbst verrät nicht, wozu er gehört.
    expect(find.text('Beitreten'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Einladungscode'), findsOneWidget);
  });

  testWidgets('Der leere Schirm nennt den Einladungscode als Weg',
      (tester) async {
    await tester.pumpWidget(_screen(const []));
    await tester.pump();

    final hinweis = tester.widget<Text>(find.byWidgetPredicate((w) =>
        w is Text && (w.data ?? '').contains('keine öffentlichen Ligen')));
    expect(hinweis.data, contains('Einladungscode'),
        reason: 'ein Leerzustand ohne Ausweg ist eine Sackgasse');
  });
}
