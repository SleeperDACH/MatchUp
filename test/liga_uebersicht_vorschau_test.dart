import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_league_screen.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **Liga-Übersicht** (erster Reiter).
///
/// Für diesen Schirm gab es lange keine — er hängt an einem Dutzend Provider,
/// und die Diagnose stand auf einem Gerätebild. Genau deshalb ist er auch nie
/// nachgebessert worden: Wer ihn ändert, sieht ihn sonst nur, wenn die eigene
/// Liga zufällig im richtigen Zustand ist.
///
/// Gezeigt wird die **laufende Saison** — der Zustand, in dem die beiden
/// Zeilengruppen „Mein Team" und „Liga" vollständig dastehen.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1999, 1, 1),
      nationality: 'DE',
    );

void main() {
  setUpAll(() async {
    await ladeSchrift();
    // Der Spieltags-Block formatiert Datumsangaben auf Deutsch.
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    // Der Ungelesen-Hinweis am Liga-Chat holt seine Lesemarke von dort;
    // ohne Mock wirft der Plugin-Kanal im Test.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Vorschau: Liga-Übersicht', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 950 * 3);
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
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 4,
      tipEnabled: true,
    );

    final pool = [
      _p('a1', 'Jonas Urbig', PlayerPosition.gk, 'FC Bayern München'),
      _p('a2', 'Nico Schlotterbeck', PlayerPosition.def, 'Borussia Dortmund'),
      _p('a3', 'Florian Wirtz', PlayerPosition.mid, 'RB Leipzig'),
      _p('a4', 'Randal Kolo Muani', PlayerPosition.fwd, 'Eintracht Frankfurt'),
    ];

    Fixture spiel(String h, String a, DateTime k, FixtureStatus st,
            [int? hs, int? as_]) =>
        Fixture(
          id: 'sportmonks:${h.hashCode}',
          leagueId: 'bundesliga',
          season: 2026,
          round: 3,
          roundName: 'Spieltag 3',
          kickoff: k,
          home: TeamRef(id: h, name: h, shortName: h),
          away: TeamRef(id: a, name: a, shortName: a),
          status: st,
          homeScore: hs,
          awayScore: as_,
        );
    final spiele = [
      spiel('FC Bayern München', 'VfB Stuttgart', DateTime(2026, 9, 12, 20, 30),
          FixtureStatus.finished, 2, 1),
      spiel('Borussia Dortmund', 'RB Leipzig', DateTime(2026, 9, 13, 15, 30),
          FixtureStatus.live, 1, 1),
      spiel('Eintracht Frankfurt', 'SC Freiburg',
          DateTime(2026, 9, 13, 15, 30), FixtureStatus.scheduled),
    ];

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
          draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
          fantasyCurrentRoundProvider.overrideWith((ref) async => 3),
          fantasyManagersProvider.overrideWith(
            (ref, id) => Stream.value(const [
              FantasyManager(userId: 'ich', username: 'SFV03', draftPosition: 1),
              FantasyManager(
                  userId: 'gegner',
                  username: 'lennartruepke',
                  draftPosition: 2),
            ]),
          ),
          leagueTradesProvider.overrideWith((ref, id) => Stream.value(const [])),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          // Zwei Wechsel, damit die Transfers-Zeile ihren Hinweis zeigt — mit
          // leerer Liste stünde dort nur das Wort, und genau das war der
          // Vorwurf an die Zeilen vor der Überarbeitung.
          rosterMovesProvider.overrideWith((ref, id) => Stream.value([
                RosterMove(
                    id: 2,
                    leagueId: 'l1',
                    managerId: 'gegner',
                    playerId: 'a3',
                    zugang: true,
                    weg: 'fa',
                    passiertAm: DateTime(2026, 9, 12, 18)),
                RosterMove(
                    id: 1,
                    leagueId: 'l1',
                    managerId: 'gegner',
                    playerId: 'a4',
                    zugang: false,
                    passiertAm: DateTime(2026, 9, 12, 17, 59)),
              ])),
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith(
            (ref, id) => Stream.value([
              for (final p in pool)
                RosterEntry(
                    managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
            ]),
          ),
          leagueLineupsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          roundStatsProvider.overrideWith((ref, round) async => const {}),
          fantasySeasonFixturesProvider
              .overrideWith((ref) async => spiele),
          fantasyTipRoundProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FantasyLeagueScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(FantasyLeagueScreen),
      matchesGoldenFile('goldens/liga_uebersicht_vorschau.png'),
    );
  });
}
