import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/favorites/favorites.dart';
import 'package:matchup/features/favorites/ui/vereinswahl_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/schrift.dart';

// Vereinsauswahl beim ersten Start (Punkt 5 der Nutzer-Analyse):
//   flutter test --update-goldens test/vereinswahl_test.dart
// -> test/goldens/vereinswahl.png

class _Speicher extends FavoritesRepository {
  _Speicher()
      : super(SupabaseClient('https://x.supabase.co', 'k',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final gespeichert = <Favorite>[];

  @override
  Future<List<Favorite>> load() async => const [];

  @override
  Future<void> add(Favorite fav) async => gespeichert.add(fav);
}

TeamRef _t(String id, String name) =>
    TeamRef(id: 'sportmonks:$id', name: name, shortName: name);

final _teams = [
  _t('503', 'FC Bayern München'),
  _t('68', 'Borussia Dortmund'),
  _t('3320', '1. FC Köln'),
  _t('2708', 'Hamburger SV'),
  _t('67', 'FC Schalke 04'),
  _t('82', 'VfL Wolfsburg'),
  _t('90', 'SC Freiburg'),
  _t('277', 'RB Leipzig'),
  _t('366', 'Werder Bremen'),
];

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Weiter erst ab einem Verein, gespeichert wird beim Weiter',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final speicher = _Speicher();
    final behaelter = ProviderContainer(overrides: [
      favoritesProvider.overrideWith((ref) => FavoritesNotifier(speicher)),
      leagueTeamsProvider
          .overrideWith((ref, id) => AsyncValue.data(_teams)),
    ]);
    addTearDown(behaelter.dispose);
    // Wie in der App: Das Gate hört von Anfang an zu, das Laden läuft also.
    behaelter.listen(vereinsWahlNoetigProvider, (_, _) {});

    await tester.pumpWidget(UncontrolledProviderScope(
      container: behaelter,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const VereinsWahlScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    FilledButton weiter() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Weiter'));

    // Geladen und noch nichts gewählt: Die Auswahl ist nötig, „Weiter" aus.
    expect(behaelter.read(vereinsWahlNoetigProvider), isTrue);
    expect(find.text('Mindestens einen Verein wählen'), findsOneWidget);
    expect(weiter().onPressed, isNull);

    await tester.tap(find.text('Hannover').evaluate().isEmpty
        ? find.text('Hamburg')
        : find.text('Hannover'));
    await tester.tap(find.text('Freiburg'));
    await tester.pumpAndSettle();
    expect(find.text('2 Vereine gewählt'), findsOneWidget);
    expect(weiter().onPressed, isNotNull);
    // Noch nicht gespeichert — erst „Weiter" schreibt.
    expect(speicher.gespeichert, isEmpty);

    await expectLater(find.byType(VereinsWahlScreen),
        matchesGoldenFile('goldens/vereinswahl.png'));

    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    expect(speicher.gespeichert.map((f) => f.label),
        ['Hamburger SV', 'SC Freiburg']);
    expect(behaelter.read(vereinsWahlNoetigProvider), isFalse);
  });
}
