import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_league_screen.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **frisch erstellten Liga** (vor dem Draft):
///   flutter test --update-goldens test/liga_vor_dem_draft_vorschau_test.dart
///   -> test/goldens/liga_vor_dem_draft.png
///
/// Der Kasten „Als Nächstes" oben stand vorher in keiner Vorschau — gemeldet
/// am 19.10.2026 als „zusammengequetscht". Zwei von zehn Plätzen belegt, der
/// Ersteller schaut drauf, damit beide Knöpfe im Bild sind. Dazu die
/// Rückfrage nach „Draft starten" (`draft_starten_blatt.png`).
void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Vorschau: Liga vor dem Draft', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = FantasyLeague(
      id: 'l1',
      name: 'Büro-Liga',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.m1,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.setup,
      createdBy: 'ich',
      maxTeams: 10,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'ich',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
        fantasyCurrentRoundProvider.overrideWith((ref) async => 7),
        fantasyManagersProvider.overrideWith((ref, id) => Stream.value(const [
              FantasyManager(userId: 'ich', username: 'SFV03'),
              FantasyManager(userId: 'b', username: 'lennartruepke'),
            ])),
        leagueTradesProvider.overrideWith((ref, id) => Stream.value(const [])),
        myWaiverClaimsProvider.overrideWith((ref, id) => Stream.value(const [])),
        rosterMovesProvider.overrideWith((ref, id) => Stream.value(const [])),
        playerPoolProvider.overrideWith((ref) async => const []),
        clubIconsProvider.overrideWith((ref) async => const {}),
        leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [])),
        leagueLineupsProvider.overrideWith((ref, id) => Stream.value(const [])),
        roundStatsProvider.overrideWith((ref, round) async => const {}),
        fantasySeasonFixturesProvider.overrideWith((ref) async => const []),
        fantasyTipRoundProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: FantasyLeagueScreen(
            league: liga, startReiter: LigaReiter.uebersicht),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Spieler einladen'), findsWidgets);
    expect(find.text('Draft starten'), findsOneWidget);
    // Was als Nächstes passiert, steht da — mit richtigem Singular/Plural.
    expect(find.text('Noch 8 Plätze frei'), findsOneWidget);
    expect(find.textContaining('wenn alle dabei'), findsOneWidget);

    await expectLater(find.byType(FantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_vor_dem_draft.png'));

    // Die Rückfrage: ein Blatt mit den Eckdaten, kein Material-Dialog.
    await tester.tap(find.text('Draft starten'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('DRAFT STARTEN?'), findsOneWidget);
    expect(find.text('Zeit je Pick'), findsOneWidget);
    expect(find.text('1 Minute'), findsOneWidget);
    // Punkt 9: Wie der Draft abläuft, steht im Klartext da.
    expect(find.textContaining('bekommt automatisch einen Spieler'),
        findsOneWidget);

    // **Direkt im Blatt einstellbar** (19.10.2026): Zeit je Pick, Runden,
    // Reihenfolge — ohne Umweg über die Einstellungen.
    await tester.tap(find.byTooltip('Zeit je Pick erhöhen'));
    await tester.pump();
    expect(find.text('2 Minuten'), findsOneWidget);
    await tester.tap(find.byTooltip('Runden erhöhen'));
    await tester.pump();
    expect(find.text('${liga.rounds + 1}'), findsOneWidget);
    expect(find.text('Reihenfolge festlegen'), findsNothing);
    await tester.tap(find.text('Manuell'));
    await tester.pump();
    expect(find.text('Reihenfolge festlegen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/draft_starten_blatt_bearbeitet.png'));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/draft_starten_blatt.png'));

    // Abbrechen schließt, ohne zu starten.
    await tester.tap(find.text('Abbrechen'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('DRAFT STARTEN?'), findsNothing);
  });

  testWidgets('Alle Teams dabei: Draft starten ist der Hauptknopf',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = FantasyLeague(
      id: 'l1',
      name: 'Büro-Liga',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.m1,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.setup,
      createdBy: 'ich',
      maxTeams: 2,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'ich',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
        fantasyCurrentRoundProvider.overrideWith((ref) async => 7),
        fantasyManagersProvider.overrideWith((ref, id) => Stream.value(const [
              FantasyManager(userId: 'ich', username: 'SFV03'),
              FantasyManager(userId: 'b', username: 'lennartruepke'),
            ])),
        leagueTradesProvider.overrideWith((ref, id) => Stream.value(const [])),
        myWaiverClaimsProvider.overrideWith((ref, id) => Stream.value(const [])),
        rosterMovesProvider.overrideWith((ref, id) => Stream.value(const [])),
        playerPoolProvider.overrideWith((ref) async => const []),
        clubIconsProvider.overrideWith((ref) async => const {}),
        leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [])),
        leagueLineupsProvider.overrideWith((ref, id) => Stream.value(const [])),
        roundStatsProvider.overrideWith((ref, round) async => const {}),
        fantasySeasonFixturesProvider.overrideWith((ref) async => const []),
        fantasyTipRoundProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: FantasyLeagueScreen(
            league: liga, startReiter: LigaReiter.uebersicht),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Alle Teams sind dabei'), findsOneWidget);
    expect(find.text('Draft starten'), findsOneWidget);
    expect(find.textContaining('je Pick'), findsOneWidget);
    await expectLater(find.byType(FantasyLeagueScreen),
        matchesGoldenFile('goldens/liga_alle_dabei.png'));
  });
}
