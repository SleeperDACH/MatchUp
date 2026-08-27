import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_settings_screen.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/schrift.dart';

/// Vorschau der **Fantasy-Einstellungen** — kein Regressionstest:
///   flutter test --update-goldens test/fantasy_einstellungen_vorschau_test.dart
///   -> test/goldens/fantasy_einstellungen_vorschau.png
///
/// Der Schirm zeigt je nach Rolle und Draft-Zustand andere Gruppen; hier steht
/// der Fall, der am meisten enthält: Ersteller einer Liga im Aufbau, also mit
/// Liga-Identität, Admin-Bereich und Gefahrenzone.
///
/// Das Bild trägt kein Datum, der Vergleich läuft deshalb fest mit.
FantasyLeague _liga() => FantasyLeague(
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
  tipEnabled: true,
);

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Fantasy-Einstellungen', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = _liga();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Ohne echten Nutzer greift der Schirm auf `Supabase.instance` zu,
          // die es im Test nicht gibt. Die ID muss `createdBy` treffen, sonst
          // fehlen Admin-Bereich und Gefahrenzone.
          currentUserProvider.overrideWith(
            (ref) => User(
              id: 'ich',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            ),
          ),
          draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
          fantasyManagersProvider.overrideWith((ref, id) async => const []),
          fantasyTipRoundProvider.overrideWith((ref, id) async => null),
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

    await expectLater(
      find.byType(FantasyLeagueSettingsScreen),
      matchesGoldenFile('goldens/fantasy_einstellungen_vorschau.png'),
    );
  });
}
