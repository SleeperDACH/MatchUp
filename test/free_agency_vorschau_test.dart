import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/free_agency_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **Free Agency** — und zwar wegen der drei Zustände, die eine
/// Zeile am rechten Rand annehmen kann. Auf dem Gerät sieht man sie nie
/// nebeneinander: Ob ein Verein gerade spielt, hängt am Kalender.
///
/// Anlass war die Meldung „der Waiver funktioniert nicht": Ein Spieler, dessen
/// Partie schon lief, trug dasselbe grüne Plus wie ein freier — man konnte ihn
/// holen, und es passierte nichts.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998, 6, 1),
      nationality: 'DE',
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Free Agency', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const gespielt = '1. FSV Mainz 05';   // Spieltag 1 am Samstag gelaufen
    const spaeter = 'FC Augsburg';        // spielt erst Sonntag 15:30
    const ruht = 'AS Monaco';             // keine Ansetzung

    final pool = [
      _p('a', 'Hyun-seok Hong', PlayerPosition.fwd, gespielt),
      _p('b', 'Andreas Hanche-Olsen', PlayerPosition.def, gespielt),
      _p('c', 'Young-woo Seol', PlayerPosition.def, spaeter),
      _p('d', 'Marius Wolf', PlayerPosition.mid, spaeter),
      _p('e', 'Denis Zakaria', PlayerPosition.mid, ruht),
    ];

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
      maxTeams: 10,
      tipEnabled: true,
    );

    Fixture f(String h, String a, FixtureStatus st, DateTime k) => Fixture(
          id: 'sportmonks:${h.hashCode}',
          leagueId: 'bundesliga',
          season: 2026,
          round: 1,
          roundName: 'Spieltag 1',
          kickoff: k,
          home: TeamRef(id: h, name: h, shortName: h),
          away: TeamRef(id: a, name: a, shortName: a),
          status: st,
        );
    // Der Spieltag läuft noch: Mainz ist durch, Augsburg kommt erst.
    final spiele = [
      f(gespielt, 'Paderborn', FixtureStatus.finished,
          DateTime.now().subtract(const Duration(days: 1))),
      f(spaeter, 'FC Schalke 04', FixtureStatus.scheduled,
          DateTime.now().add(const Duration(hours: 8))),
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
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [])),
          // Ein Spieler liegt zusätzlich auf dem Wire — damit im Bild steht,
          // wie sich „Waiver" und „Spiel läuft" unterscheiden.
          waiverPlayersProvider.overrideWith((ref, id) => Stream.value({'e'})),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FreeAgencyScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(FreeAgencyScreen),
      matchesGoldenFile('goldens/free_agency_vorschau.png'),
    );
  });
}
