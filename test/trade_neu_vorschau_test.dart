import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/trade_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau des Schirms **„Neuer Trade"** (`TradeComposeScreen`).
///
/// Auf dem Gerät braucht er zwei volle Kader und einen Tauschpartner; hier
/// stehen sie fest. Gezeigt wird der Zustand mit **Vorauswahl auf beiden
/// Seiten** — nur dann sieht man, was die Auswahl mit dem Schirm macht.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1999, 5, 2),
      nationality: 'DE',
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Neuer Trade', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final meine = [
      _p('m1', 'Jonas Urbig', PlayerPosition.gk, 'FC Bayern München'),
      _p('m2', 'Nico Schlotterbeck', PlayerPosition.def, 'Borussia Dortmund'),
      _p('m3', 'Maximilian Mittelstädt', PlayerPosition.def, 'VfB Stuttgart'),
      _p('m4', 'Florian Wirtz', PlayerPosition.mid, 'RB Leipzig'),
      _p('m5', 'Jamal Musiala', PlayerPosition.mid, 'FC Bayern München'),
      _p('m6', 'Randal Kolo Muani', PlayerPosition.fwd, 'Eintracht Frankfurt'),
    ];
    final seine = [
      _p('s1', 'Manuel Neuer', PlayerPosition.gk, 'FC Bayern München'),
      _p('s2', 'Jonathan Tah', PlayerPosition.def, 'Bayer Leverkusen'),
      _p('s3', 'Joshua Kimmich', PlayerPosition.mid, 'FC Bayern München'),
      _p('s4', 'Serge Gnabry', PlayerPosition.mid, 'FC Bayern München'),
      _p('s5', 'Victor Boniface', PlayerPosition.fwd, 'Bayer Leverkusen'),
    ];

    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 10,
      tipEnabled: true,
    );

    const partner = FantasyManager(userId: 'gegner', username: 'lennartruepke');

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
          playerPoolProvider.overrideWith((ref) async => [...meine, ...seine]),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith(
            (ref, id) => Stream.value([
              for (final p in meine)
                RosterEntry(
                    managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
              for (final p in seine)
                RosterEntry(
                    managerId: 'gegner', playerId: p.id, acquiredVia: 'draft'),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TradeComposeScreen(
            league: liga,
            partner: partner,
            initialOffer: const {'m4'},
            initialRequest: const {'s3', 's5'},
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(TradeComposeScreen),
      matchesGoldenFile('goldens/trade_neu_vorschau.png'),
    );
  });
}
