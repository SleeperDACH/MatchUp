import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_table_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau des **Tabellen-Tabs**.
///
/// Auf dem Gerät zeigt er nur, was die eigene Liga hergibt — vor dem ersten
/// gewerteten Spieltag stehen alle auf 0-0-0, und man sieht weder Rangfolge
/// noch Bilanz. Hier stehen vier Manager mit drei gespielten Spieltagen.
FantasyPlayer _p(String id, String name, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: 'FC Test',
      birthDate: DateTime(1999),
      nationality: 'DE',
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Tabelle', (tester) async {
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
      createdBy: 'm0',
      maxTeams: 4,
      tipEnabled: true,
    );

    const namen = ['SFV03', 'lennartruepke', 'Spitzenreiter04', 'ana'];
    final manager = [
      for (var i = 0; i < namen.length; i++)
        FantasyManager(
            userId: 'm$i', username: namen[i], draftPosition: i + 1),
    ];

    // Jeder Manager bekommt elf Spieler; die Tore steuern, wer gewinnt.
    final pool = <FantasyPlayer>[];
    final roster = <RosterEntry>[];
    for (var m = 0; m < namen.length; m++) {
      for (var i = 0; i < 11; i++) {
        final pos = i == 0
            ? PlayerPosition.gk
            : i < 5
                ? PlayerPosition.def
                : i < 9
                    ? PlayerPosition.mid
                    : PlayerPosition.fwd;
        final id = 'm$m-p$i';
        pool.add(_p(id, 'Spieler $m$i', pos));
        roster.add(
            RosterEntry(managerId: 'm$m', playerId: id, acquiredVia: 'draft'));
      }
    }

    // Drei gewertete Spieltage; Manager 0 am stärksten, 3 am schwächsten.
    final seasonStats = <int, Map<String, PlayerMatchStats>>{
      for (var runde = 1; runde <= 3; runde++)
        runde: {
          for (var m = 0; m < namen.length; m++)
            for (var i = 0; i < 11; i++)
              'm$m-p$i': PlayerMatchStats(
                minutes: 90,
                played: true,
                goals: (i + runde + m) % (m + 2) == 0 ? 1 : 0,
              ),
        }
    };

    // Drei abgepfiffene Spieltage — nur die tauchen im Rückblick auf.
    final spiele = [
      for (var runde = 1; runde <= 3; runde++)
        Fixture(
          id: 'sportmonks:$runde',
          leagueId: 'bundesliga',
          season: 2026,
          round: runde,
          roundName: 'Spieltag $runde',
          kickoff: DateTime(2026, 8, 10 + runde, 15, 30),
          home: const TeamRef(id: 'h', name: 'Heim', shortName: 'H'),
          away: const TeamRef(id: 'a', name: 'Gast', shortName: 'G'),
          status: FixtureStatus.finished,
          homeScore: 1,
          awayScore: 0,
        ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'm0',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          fantasyManagersProvider
              .overrideWith((ref, id) => Stream.value(manager)),
          playerPoolProvider.overrideWith((ref) async => pool),
          leagueRosterProvider.overrideWith((ref, id) => Stream.value(roster)),
          leagueLineupsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          seasonStatsProvider.overrideWith((ref) async => seasonStats),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
          fantasyCurrentRoundProvider.overrideWith((ref) async => 3),
          clubIconsProvider.overrideWith((ref) async => const {}),
          for (var r = 1; r <= 3; r++)
            roundStatsProvider(r)
                .overrideWith((ref) async => seasonStats[r] ?? const {}),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: FantasyTableBody(league: liga)),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(FantasyTableBody),
      matchesGoldenFile('goldens/fantasy_tabelle_vorschau.png'),
    );
  });
}
