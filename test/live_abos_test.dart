import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/favorites/favorites.dart';
import 'package:matchup/features/push/live_abos.dart';
import 'package:matchup/features/push/ui/live_abos_screen.dart';

import 'support/schrift.dart';

/// Live-Push für Vereine und ganze Ligen (20.10.2026, Migration 0142).
///   flutter test --update-goldens test/live_abos_test.dart
class _FesteFavoriten extends FavoritesNotifier {
  _FesteFavoriten(List<Favorite> favs) : super(null) {
    state = favs;
  }
}

const _teams = [
  TeamRef(id: 'sportmonks:503', name: 'FC Bayern München', shortName: 'FCB'),
  TeamRef(id: 'sportmonks:68', name: 'Borussia Dortmund', shortName: 'BVB'),
  TeamRef(id: 'sportmonks:67', name: 'FC Schalke 04', shortName: 'S04'),
  TeamRef(id: 'sportmonks:3320', name: '1. FC Köln', shortName: 'KOE'),
];

void main() {
  setUpAll(ladeSchrift);

  group('Modell', () {
    test('Zusammenfassung', () {
      expect(const LiveAbos().zusammenfassung, 'Nur Favoriten');
      final a = const LiveAbos()
          .mitVerein('sportmonks:68', true)
          .mitVerein('sportmonks:67', true)
          .mitLiga('liga3', true);
      expect(a.zusammenfassung, '2 Vereine · 1 Liga');
      expect(a.mitVerein('sportmonks:68', false).vereine, {'sportmonks:67'});
      expect(a.mitLiga('liga3', false).ligen, isEmpty);
    });

    test('Wettbewerbe passen zum Check der Datenbank', () {
      expect(LiveAbos.wettbewerbe.map((l) => l.id).toSet(), {
        'bundesliga', 'bundesliga2', 'liga3', 'frauen_bundesliga', 'dfb_pokal',
      });
    });
  });

  Future<void> zeige(WidgetTester tester, LiveAbos abos) async {
    tester.view.physicalSize = const Size(402 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        liveAbosProvider.overrideWith((ref) async => abos),
        leagueTeamsProvider
            .overrideWith((ref, id) => const AsyncValue.data(_teams)),
        favoritesProvider.overrideWith((ref) => _FesteFavoriten([
              Favorite.team(_teams.first, 'bundesliga'),
            ])),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const LiveAboLigaScreen(liga: Leagues.bundesliga),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  List<Switch> schalter(WidgetTester tester) =>
      tester.widgetList<Switch>(find.byType(Switch)).toList();

  testWidgets('Favorit fest an, Abo an, Rest aus', (tester) async {
    await zeige(tester, const LiveAbos(vereine: {'sportmonks:68'}));
    expect(find.text('Favorit'), findsOneWidget);
    // Alle Vereine + drei Vereine; der Favorit trägt ein Häkchen.
    final s = schalter(tester);
    expect(s, hasLength(4));
    expect(s[0].value, isFalse);
    expect(find.byIcon(Icons.check), findsOneWidget,
        reason: 'Favorit meldet ohnehin');
    expect(s[1].value, isTrue);
    expect(s[2].value, isFalse);
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/live_abos_liga.png'));
  });

  testWidgets('Ganze Liga: jeder Verein an und gesperrt', (tester) async {
    await zeige(tester, const LiveAbos(ligen: {'bundesliga'}));
    final s = schalter(tester);
    expect(s, hasLength(1), reason: 'nur noch „Alle Vereine"');
    expect(s.single.value, isTrue);
    expect(find.byIcon(Icons.check), findsNWidgets(4));
    expect(find.text('Über die ganze Liga'), findsNWidgets(3));
  });
}
