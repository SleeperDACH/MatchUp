import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/data/fantasy_league_repository.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_settings_screen.dart';
import 'package:matchup/features/tippspiel/models/tip.dart';
import 'package:matchup/features/tippspiel/models/tip_round.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/schrift.dart';

/// **Der Tippspiel-Schalter fragt nach — und geht in beide Richtungen.**
///
/// Gemeldet: „Wenn man in den Ligaeinstellungen das Tippspiel aktiviert, wird
/// es direkt gemacht ohne Nachfragen. Außerdem fehlt die Option, es zu
/// deaktivieren."
///
/// Beides hing zusammen: Die Zeile schaltete sofort ein **und** verschwand
/// danach, weil sie nur bei `!tipEnabled` gezeigt wurde. Ein Fingertipp
/// daneben war damit endgültig.
class _MerkendesRepo extends FantasyLeagueRepository {
  _MerkendesRepo(super.client);

  final gesetzt = <bool>[];

  @override
  Future<void> setTipEnabled(String leagueId, bool enabled) async =>
      gesetzt.add(enabled);
}

FantasyLeague _liga({required bool tipEnabled}) => FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.setup,
      createdBy: 'ich',
      maxTeams: 10,
      tipEnabled: tipEnabled,
    );

Future<_MerkendesRepo> _aufbauen(
  WidgetTester tester, {
  required bool tipEnabled,
  TipRound? runde,
}) async {
  final vorher = AppConfig.supabaseInitialized;
  AppConfig.supabaseInitialized = true;
  addTearDown(() => AppConfig.supabaseInitialized = vorher);

  // **Hoher Schirm mit Absicht.** Die Tippspiel-Gruppe sitzt weit unten in
  // einer Liste; auf einem Telefonschirm ist sie schlicht nicht gebaut, und
  // `find.text` findet nur Gebautes. Scrollen im Test wäre der Umweg — die
  // Liste ist hier nicht der Prüfgegenstand.
  tester.view.physicalSize = const Size(402 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final liga = _liga(tipEnabled: tipEnabled);
  // **Ohne `autoRefreshToken: false` hinterlässt der Client einen Timer**, und
  // der Test scheitert am Ende an „A Timer is still pending". Angesprochen
  // wird der Client hier ohnehin nie — `setTipEnabled` ist überschrieben.
  final client = SupabaseClient('http://localhost', 'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  final repo = _MerkendesRepo(client);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'ich',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        fantasyLeagueRepositoryProvider.overrideWithValue(repo),
        draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
        fantasyManagersProvider.overrideWith((ref, id) => Stream.value(const [])),
        fantasyTipRoundProvider.overrideWith((ref, id) async => runde),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: FantasyLeagueSettingsScreen(league: liga),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return repo;
}

Future<void> _tippeZeile(WidgetTester tester, String text) async {
  // `ensureVisible` statt `scrollUntilVisible`: Letzteres sucht in einer
  // Schleife und läuft **endlos**, wenn der Text nicht auftaucht — der Test
  // hängt dann, statt zu scheitern.
  final zeile = find.text(text);
  expect(zeile, findsOneWidget);
  await tester.ensureVisible(zeile);
  await tester.pumpAndSettle();
  await tester.tap(zeile);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Einschalten passiert erst nach der Rückfrage', (tester) async {
    final repo = await _aufbauen(tester, tipEnabled: false);

    await _tippeZeile(tester, 'Ligainternes Tippspiel einschalten');
    expect(find.text('Tippspiel einschalten?'), findsOneWidget,
        reason: 'Der Tipp muss fragen, nicht handeln');
    expect(repo.gesetzt, isEmpty,
        reason: 'Vor der Antwort darf nichts geschrieben werden');

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(repo.gesetzt, isEmpty, reason: 'Abbrechen heißt abbrechen');

    await _tippeZeile(tester, 'Ligainternes Tippspiel einschalten');
    await tester.tap(find.widgetWithText(FilledButton, 'Einschalten'));
    await tester.pumpAndSettle();
    expect(repo.gesetzt, [true]);
  });

  testWidgets('Ausschalten gibt es auch — und ebenfalls mit Rückfrage',
      (tester) async {
    final repo = await _aufbauen(tester, tipEnabled: true);

    await _tippeZeile(tester, 'Ligainternes Tippspiel ausschalten');
    expect(find.text('Tippspiel ausschalten?'), findsOneWidget);
    expect(repo.gesetzt, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Ausschalten'));
    await tester.pumpAndSettle();
    expect(repo.gesetzt, [false]);
  });

  testWidgets('Steht die Runde, verspricht der Schirm keinen Schalter mehr',
      (tester) async {
    // Die Übersicht zeigt das Tippspiel, sobald es **eine Runde gibt** — der
    // Merker allein bewirkt dann nichts mehr. Ein Schalter, der nichts tut,
    // wäre schlimmer als keiner.
    final repo = await _aufbauen(
      tester,
      tipEnabled: true,
      runde: TipRound(
        id: 'r1',
        name: 'MatchUp! #1',
        leagueId: 'bl1',
        season: 2026,
        inviteCode: 'XYZ',
        scoring: ScoringRules.kicktippDefault,
        createdBy: 'ich',
        fantasyLeagueId: 'l1',
      ),
    );

    expect(find.text('Ligainternes Tippspiel läuft'), findsOneWidget);
    expect(find.text('Ligainternes Tippspiel ausschalten'), findsNothing);
    expect(find.text('Ligainternes Tippspiel einschalten'), findsNothing);
    expect(repo.gesetzt, isEmpty);
  });

  // **Bilder vom ganzen Schirm, nicht von der Zeile.** Eine `ListTile` allein
  // malt keinen Grund; das Golden davon war weiße Fläche auf weißer Fläche.
  // Der hohe Schirm zeigt die Einstellungen ohnehin erstmals vollständig —
  // die bisherige Vorschau reicht nur bis „Playoff-Einstellungen".
  testWidgets('Vorschau: Einstellungen mit eingeschaltetem Tippspiel',
      (tester) async {
    await _aufbauen(tester, tipEnabled: true);
    await expectLater(find.byType(FantasyLeagueSettingsScreen),
        matchesGoldenFile('goldens/fantasy_einstellungen_tippspiel_an.png'));
  });

  testWidgets('Vorschau: Einstellungen, wenn die Tipprunde schon steht',
      (tester) async {
    await _aufbauen(
      tester,
      tipEnabled: true,
      runde: TipRound(
        id: 'r1',
        name: 'MatchUp! #1',
        leagueId: 'bl1',
        season: 2026,
        inviteCode: 'XYZ',
        scoring: ScoringRules.kicktippDefault,
        createdBy: 'ich',
        fantasyLeagueId: 'l1',
      ),
    );
    await expectLater(find.byType(FantasyLeagueSettingsScreen),
        matchesGoldenFile('goldens/fantasy_einstellungen_tippspiel_laeuft.png'));
  });
}
