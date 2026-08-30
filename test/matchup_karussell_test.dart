import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/matchups_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// **Das Karussell darf beim Nachladen nicht zurückspringen.**
///
/// Gemeldet: „Wenn man zwischen den MatchUps hin und her wischt und dann nach
/// unten geht oder auf ein Spielerprofil, schmeißt es einen zurück auf das
/// erste."
///
/// Die Ursache war ein früher `return` auf `isLoading`: Er ersetzt den ganzen
/// Teilbaum, der `PageView` wird abgebaut, und beim Wiederaufbau beginnt der
/// Controller wieder bei `initialPage`. Ausgelöst hat das **jede**
/// Auffrischung — und der Spielerpool wird nachgeladen, sobald ein Profil
/// aufgeht.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('nach einem Nachladen bleibt man auf demselben MatchUp',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 4,
      tipEnabled: true,
    );

    const manager = [
      FantasyManager(userId: 'ich', username: 'SFV03', draftPosition: 1),
      FantasyManager(userId: 'b', username: 'lennartruepke', draftPosition: 2),
      FantasyManager(userId: 'c', username: 'tamara', draftPosition: 3),
      FantasyManager(userId: 'd', username: 'Majusch', draftPosition: 4),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'ich',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        fantasyManagersProvider
            .overrideWith((ref, id) => Stream.value(manager)),
        playerPoolProvider.overrideWith((ref) async => const <FantasyPlayer>[]),
        leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [])),
        leagueLineupsProvider.overrideWith((ref, id) => Stream.value(const [])),
        clubIconsProvider.overrideWith((ref) async => const {}),
        seasonStatsProvider.overrideWith((ref) async => const {}),
        roundStatsProvider.overrideWith((ref, r) async => const {}),
        fantasySeasonFixturesProvider.overrideWith((ref) async => const []),
        fantasyCurrentRoundProvider.overrideWith((ref) async => 1),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: MatchupsBody(league: liga)),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final seite = find.byType(PageView);
    expect(seite, findsOneWidget);
    int aktuelleSeite() =>
        (tester.widget<PageView>(seite).controller!.page ?? 0).round();
    final start = aktuelleSeite();

    // Einmal weiterwischen.
    await tester.drag(seite, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(aktuelleSeite(), start + 1,
        reason: 'Das Wischen muss überhaupt ankommen');

    // **Jetzt das Nachladen**, wie es ein geöffnetes Spielerprofil auslöst.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(MatchupsBody)));
    container.invalidate(playerPoolProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget,
        reason: 'Der PageView darf beim Nachladen nicht abgebaut werden');
    expect(aktuelleSeite(), start + 1,
        reason: 'Nach dem Nachladen muss dieselbe Paarung stehen');
  });
}
