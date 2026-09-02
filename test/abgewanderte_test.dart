import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/transfer_vorgaenge.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/free_agency_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Wer die Bundesliga verlässt, verschwindet aus dem Fantasy-Pool.
///
/// Bis Migration 0117 blieb er stehen, sobald irgendetwas auf ihn zeigte —
/// gedraftet, gerostert oder einmal gewertet. Er trug seinen alten Verein an
/// der Karte, war in der Free Agency zu holen und belegte im Kader seines
/// Managers einen Platz, auf dem er bis Saisonende null Punkte bringt.
///
/// Seine Zeile bleibt trotzdem geladen: Das Draft-Brett und die gespielten
/// Spieltage brauchen den Namen. Ausgeblendet wird er nur dort, wo man
/// jemanden holen kann.
FantasyPlayer _p(
  String id,
  String name,
  PlayerPosition pos,
  String club, {
  DateTime? abgangAm,
}) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998, 6, 1),
      nationality: 'DE',
      abgangAm: abgangAm,
    );

void main() {
  setUpAll(ladeSchrift);

  group('Die Markierung', () {
    test('kommt aus der Datenbank und fehlt beim normalen Spieler', () {
      final da = FantasyPlayer.fromJson(const {
        'id': 'sportmonks:1',
        'name': 'Marius Wolf',
        'position': 'mid',
        'club': 'FC Augsburg',
        'birth_date': '1995-05-27',
        'nationality': 'de',
      });
      expect(da.abgewandert, isFalse);

      final weg = FantasyPlayer.fromJson(const {
        'id': 'sportmonks:2',
        'name': 'Serhou Guirassy',
        'position': 'fwd',
        'club': 'Borussia Dortmund',
        'birth_date': '1996-03-12',
        'nationality': 'gn',
        'abgang_am': '2026-09-02T04:17:00Z',
      });
      expect(weg.abgewandert, isTrue);
      expect(weg.abgangAm!.toUtc(), DateTime.utc(2026, 9, 2, 4, 17));
    });
  });

  group('Die Kaderbewegung', () {
    RosterMove abgang(String? weg) => RosterMove(
          id: 1,
          leagueId: 'l1',
          managerId: 'm1',
          playerId: 'p1',
          zugang: false,
          weg: weg,
          passiertAm: DateTime(2026, 9, 2, 6, 17),
        );

    test('heißt nicht „Abgegeben", wenn der Spieler die Liga verlassen hat',
        () {
      // Sonst läse es sich wie eine Entscheidung des Managers.
      expect(abgang('abgewandert').bezeichnung, 'Bundesliga verlassen');
      expect(abgang(null).bezeichnung, 'Abgegeben');
      expect(abgang('trade').bezeichnung, 'Getradet');
    });

    test('trägt denselben Namen im zusammengefassten Vorgang', () {
      final vorgaenge = vorgaengeAus([abgang('abgewandert')]);
      expect(vorgaenge.single.nurAbgang, isTrue);
      expect(vorgaenge.single.bezeichnung, 'Bundesliga verlassen');
    });
  });

  testWidgets('Die Free Agency zeigt einen Abgewanderten nicht mehr',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const augsburg = 'FC Augsburg';
    final pool = [
      _p('a', 'Marius Wolf', PlayerPosition.mid, augsburg),
      // Er stand bis zum Sommer bei Dortmund; der Kader-Sync fand ihn dort
      // nicht mehr. Sein Verein steht weiter in der Zeile — genau deshalb
      // fiel er vorher nicht auf.
      _p('b', 'Serhou Guirassy', PlayerPosition.fwd, 'Borussia Dortmund',
          abgangAm: DateTime(2026, 9, 2, 6, 17)),
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

    final spiele = [
      Fixture(
        id: 'sportmonks:1',
        leagueId: 'bundesliga',
        season: 2026,
        round: 1,
        roundName: 'Spieltag 1',
        kickoff: DateTime(2026, 8, 30, 17, 30),
        home: const TeamRef(id: augsburg, name: augsburg, shortName: 'FCA'),
        away: const TeamRef(
            id: 'FC Schalke 04', name: 'FC Schalke 04', shortName: 'S04'),
        status: FixtureStatus.scheduled,
      ),
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
          leagueRosterProvider
              .overrideWith((ref, id) => Stream.value(const <RosterEntry>[])),
          fantasyManagersProvider.overrideWith((ref, id) => Stream.value(const [
                FantasyManager(userId: 'ich', username: 'SFV03'),
              ])),
          seasonStatsProvider.overrideWith((ref) async => const {}),
          waiverPlayersProvider
              .overrideWith((ref, id) => Stream.value(const <String>{})),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
          absencesProvider.overrideWith((ref) => Stream.value(const {})),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FreeAgencyScreen(
              league: liga, jetzt: DateTime(2026, 8, 29, 18)),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Marius Wolf'), findsOneWidget);
    expect(find.text('Serhou Guirassy'), findsNothing,
        reason: 'Er ist nicht mehr zu holen — auch nicht mit Suche und Filter');
  });
}
