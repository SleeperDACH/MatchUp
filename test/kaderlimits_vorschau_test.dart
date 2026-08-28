import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_settings_screen.dart';

import 'support/schrift.dart';

/// Vorschau der **Kader-Limits** — kein Regressionstest:
///   flutter test --update-goldens test/kaderlimits_vorschau_test.dart
///
/// Gezeigt wird der **gemischte** Fall: Torhüter und Sturm sind begrenzt,
/// Abwehr und Mittelfeld nicht. Genau das muss man auf einen Blick
/// unterscheiden können — eine Zahl heißt begrenzt, „ohne Limit" heißt offen.
/// Dazu ein Kader, der ein Limit schon reißt (acht Stürmer): Der Hinweis muss
/// sagen, dass er seine Spieler behält.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Kader-Limits', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: const RosterConfig(maxGk: 2, maxFwd: 5),
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 4,
      tipEnabled: true,
    );

    // Ein Kader mit acht Stürmern — über dem Limit von 5.
    final pool = [
      for (var i = 0; i < 8; i++)
        FantasyPlayer(
          id: 'st$i',
          name: 'Stürmer $i',
          position: PlayerPosition.fwd,
          club: 'FC Test',
          birthDate: DateTime(2000),
          nationality: 'DE',
        ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerPoolProvider.overrideWith((ref) async => pool),
          leagueRosterProvider.overrideWith(
            (ref, id) => Stream.value([
              for (final p in pool)
                RosterEntry(
                    managerId: 'm1', playerId: p.id, acquiredVia: 'draft'),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: KaderLimitsPage(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(KaderLimitsPage),
      matchesGoldenFile('goldens/kaderlimits_vorschau.png'),
    );
  });
}
