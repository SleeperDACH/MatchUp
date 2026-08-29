import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/player_profile_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau des **Spielerprofils**.
///
/// Seit das Wappen nicht mehr auf die Vereinsseite führt, muss das Profil
/// hergeben, wofür man dorthin ging: Leistung, Spielplan und Kader. Die drei
/// Reiter stehen hier nebeneinander — auf dem Gerät sieht man immer nur einen.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1999, 4, 12),
      nationality: 'DE',
    );

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

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

  const club = 'Borussia Dortmund';
  final held = _p('p1', 'Nico Schlotterbeck', PlayerPosition.def, club);
  final pool = [
    held,
    _p('p2', 'Gregor Kobel', PlayerPosition.gk, club),
    _p('p3', 'Julian Brandt', PlayerPosition.mid, club),
    _p('p4', 'Serhou Guirassy', PlayerPosition.fwd, club),
    _p('p9', 'Jamal Musiala', PlayerPosition.mid, 'FC Bayern München'),
  ];

  final saison = <int, Map<String, PlayerMatchStats>>{
    1: {
      'p1': const PlayerMatchStats(
          minutes: 90, played: true, cleanSheet: true, tacklesWon: 4),
    },
    2: {
      'p1': const PlayerMatchStats(
          minutes: 74, played: true, goalsConceded: 3, yellow: 1),
    },
    3: {'p1': const PlayerMatchStats()},
  };

  final spiele = [
    for (var r = 1; r <= 3; r++)
      Fixture(
        id: 'sportmonks:$r',
        leagueId: 'bundesliga',
        season: 2026,
        round: r,
        roundName: 'Spieltag $r',
        kickoff: DateTime(2026, 8, 14 + r * 7, 15, 30),
        home: r.isOdd
            ? const TeamRef(id: 'bvb', name: club, shortName: 'BVB')
            : const TeamRef(
                id: 'fcb', name: 'FC Bayern München', shortName: 'FCB'),
        away: r.isOdd
            ? const TeamRef(
                id: 'fcb', name: 'FC Bayern München', shortName: 'FCB')
            : const TeamRef(id: 'bvb', name: club, shortName: 'BVB'),
        status: r < 3 ? FixtureStatus.finished : FixtureStatus.scheduled,
        homeScore: r < 3 ? 2 : null,
        awayScore: r < 3 ? 1 : null,
      ),
  ];

  Widget rahmen(Widget kind) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'ich',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          seasonStatsProvider.overrideWith((ref) async => saison),
          leagueRosterProvider.overrideWith(
            (ref, id) => Stream.value([
              RosterEntry(
                  managerId: 'ich', playerId: 'p1', acquiredVia: 'draft'),
            ]),
          ),
          fantasyManagersProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: kind),
      );

  testWidgets('Vorschau: Spielerprofil', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlayerProfile(
              context,
              league: liga,
              player: held,
              clubIcon: null,
              isMine: true,
            ),
            child: const Text('öffnen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('öffnen'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(BottomSheet),
      matchesGoldenFile('goldens/spielerprofil_leistung.png'),
    );

    // Spielplan und Kader — die beiden Reiter, die es ohne den Wegfall der
    // Vereinsseite gar nicht bräuchte.
    await tester.tap(find.text('Spielplan'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await expectLater(
      find.byType(BottomSheet),
      matchesGoldenFile('goldens/spielerprofil_spielplan.png'),
    );

    await tester.tap(find.text('Kader'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await expectLater(
      find.byType(BottomSheet),
      matchesGoldenFile('goldens/spielerprofil_kader.png'),
    );

    await tester.tap(find.text('Leistung'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Ein Spieltag mit gemischter Bilanz: 74 Minuten, drei Gegentore, Gelb.
    // Genau da sagt die Punktzahl allein nichts.
    await tester.tap(find.text('2.'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await expectLater(
      find.byType(BottomSheet).last,
      matchesGoldenFile('goldens/spielerprofil_aufschluesselung.png'),
    );
  });
}
