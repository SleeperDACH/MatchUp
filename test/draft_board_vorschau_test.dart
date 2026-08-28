import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/draft_board_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau des **Draft-Boards zum Nachschauen** — kein Regressionstest:
///   flutter test --update-goldens test/draft_board_vorschau_test.dart
///
/// Der Schirm ist nach dem Draft über die Liga-Einstellungen erreichbar. Auf
/// dem Gerät bekommt man ihn nur mit einer fertig gedrafteten Liga zu sehen;
/// hier steht sie fest. Fester Bildvergleich — kein Datum im Bild.
const _teams = ['Nord', 'Süd', 'Ost', 'West'];

FantasyLeague _liga() => FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.done,
      createdBy: 'u0',
      maxTeams: 4,
      tipEnabled: true,
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Draft-Board', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 620 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = _liga();
    final manager = [
      for (var i = 0; i < _teams.length; i++)
        FantasyManager(
            userId: 'u$i', username: _teams[i], draftPosition: i + 1),
    ];
    // Vier Runden Snake: 1..4, dann 4..1, usw.
    final picks = <DraftPick>[];
    final spieler = <FantasyPlayer>[];
    var nr = 1;
    for (var r = 1; r <= 4; r++) {
      final reihe = r.isOdd
          ? [0, 1, 2, 3]
          : [3, 2, 1, 0];
      for (final slot in reihe) {
        final id = 'p$nr';
        spieler.add(FantasyPlayer(
          id: id,
          name: 'Spieler $nr',
          position: PlayerPosition.values[nr % PlayerPosition.values.length],
          club: 'FC Test',
          birthDate: DateTime(2000),
          nationality: 'DE',
        ));
        picks.add(DraftPick(
          phase: DraftPhase.startup,
          pickNumber: nr,
          round: r,
          managerId: 'u$slot',
          playerId: id,
          // Jeder dritte Pick kam automatisch — zeigt das AUTO-Abzeichen.
          isAuto: nr % 3 == 0,
        ));
        nr++;
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'u1',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
          draftPicksProvider.overrideWith((ref, id) => Stream.value(picks)),
          fantasyManagersProvider
              .overrideWith((ref, id) => Stream.value(manager)),
          playerPoolProvider.overrideWith((ref) async => spieler),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: DraftBoardScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(DraftBoardScreen),
      matchesGoldenFile('goldens/draft_board_vorschau.png'),
    );
  });
}
