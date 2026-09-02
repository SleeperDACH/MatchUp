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
import 'package:matchup/features/fantasy/models/player_absence.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/lineup_screen.dart';
import 'package:matchup/features/fantasy/data/fantasy_league_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient, User;

import 'support/schrift.dart';

/// **Das Spielfeld im Kader-Tab** — der Schirm hatte keine Vorschau, und
/// genau deshalb ließ sich sein Aussehen bisher nur auf dem Gerät beurteilen,
/// im Zustand, in dem die eigene Liga gerade war.
///
/// Zwei Bilder, weil es zwei Zustände gibt, die man nie nebeneinander sieht:
/// die Elf, an der man noch etwas ändern kann, und die, an der nichts mehr
/// geht (alle Spiele laufen).
///
/// **Der Bildvergleich läuft nur mit `--update-goldens`**: Ob ein Spieler
/// gesperrt ist, hängt an `DateTime.now()` gegen den Anpfiff seines Vereins —
/// ein fest eingecheckter Vergleich wäre in ein paar Tagen rot, ohne dass
/// jemand etwas geändert hätte. Was gehalten werden muss, steht als Messung
/// daneben.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998, 3, 4),
      nationality: 'de',
    );

/// Ein Repository, das nichts tut: Der Editor liest es im `initState` (für
/// den Flush aus `dispose`), und ohne Ersatz greift er auf `Supabase.instance`
/// zu, die es im Test nicht gibt.
class _StillesRepo extends FantasyLeagueRepository {
  _StillesRepo(super.client);

  @override
  Future<void> setLineup(String leagueId, int round, List<String> ids) async {}
}

void main() {
  setUpAll(ladeSchrift);

  const bvb = 'Borussia Dortmund';
  const fcb = 'FC Bayern München';
  const sge = 'Eintracht Frankfurt';

  final elf = <FantasyPlayer>[
    _p('gk1', 'Gregor Kobel', PlayerPosition.gk, bvb),
    _p('d1', 'Nico Schlotterbeck', PlayerPosition.def, bvb),
    _p('d2', 'Waldemar Anton', PlayerPosition.def, bvb),
    _p('d3', 'Maximilian Mittelstädt', PlayerPosition.def, fcb),
    _p('d4', 'Julian Ryerson', PlayerPosition.def, bvb),
    _p('m1', 'Jobe Bellingham', PlayerPosition.mid, bvb),
    _p('m2', 'Felix Nmecha', PlayerPosition.mid, bvb),
    _p('m3', 'Jamal Musiala', PlayerPosition.mid, fcb),
    _p('m4', 'Karim Adeyemi', PlayerPosition.mid, bvb),
    _p('f1', 'Serhou Guirassy', PlayerPosition.fwd, bvb),
    _p('f2', 'Randal Kolo Muani', PlayerPosition.fwd, sge),
  ];
  final bank = <FantasyPlayer>[
    _p('b1', 'Alexander Meyer', PlayerPosition.gk, bvb),
    _p('b2', 'Emre Can', PlayerPosition.mid, bvb),
    _p('b3', 'Yan Couto', PlayerPosition.def, bvb),
    _p('b4', 'Marcel Sabitzer', PlayerPosition.mid, bvb),
  ];
  final pool = [...elf, ...bank];

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

  // Punkte: eine Spanne von Minus bis zweistellig, damit die Zahl im Bild
  // beurteilt werden kann — sie war der Anlass („die Punkte sind zu klein").
  final stats = <String, PlayerMatchStats>{
    'gk1': const PlayerMatchStats(minutes: 90, played: true, saves: 4, cleanSheet: true),
    'd1': const PlayerMatchStats(minutes: 90, played: true, cleanSheet: true, tacklesWon: 3),
    'd2': const PlayerMatchStats(minutes: 90, played: true, goalsConceded: 2, yellow: 1),
    'd3': const PlayerMatchStats(minutes: 74, played: true, cleanSheet: true),
    'd4': const PlayerMatchStats(minutes: 90, played: true, assists: 1),
    'm1': const PlayerMatchStats(minutes: 90, played: true, goals: 1, keyPasses: 2),
    'm2': const PlayerMatchStats(minutes: 63, played: true, fouls: 3),
    'm3': const PlayerMatchStats(minutes: 90, played: true, goals: 2, assists: 1),
    'm4': const PlayerMatchStats(minutes: 21, played: true),
    'f1': const PlayerMatchStats(minutes: 90, played: true, goals: 1),
    'f2': const PlayerMatchStats(minutes: 90, played: true, shotsOnTarget: 3),
  };

  /// [gelaufen] nennt die Vereine, deren Spiel schon angepfiffen ist — daran
  /// hängt die Sperre je Spieler (Migration 0084).
  List<Fixture> spiele({required Set<String> gelaufen}) {
    final jetzt = DateTime.now();
    Fixture f(String heim, String gast) => Fixture(
          id: 'sportmonks:${heim.hashCode}',
          leagueId: 'bundesliga',
          season: 2026,
          round: 1,
          roundName: 'Spieltag 1',
          kickoff: gelaufen.contains(heim)
              ? jetzt.subtract(const Duration(minutes: 40))
              : jetzt.add(const Duration(days: 2)),
          home: TeamRef(id: heim, name: heim, shortName: heim),
          away: TeamRef(id: gast, name: gast, shortName: gast),
          status: FixtureStatus.scheduled,
        );
    // Frankfurt spielt gegen Bayern — beide hängen an derselben Ansetzung.
    return [f(bvb, 'FC Augsburg'), f(fcb, sge)];
  }

  Widget rahmen({required Set<String> gelaufen}) => ProviderScope(
        overrides: [
          fantasyLeagueRepositoryProvider.overrideWithValue(
            _StillesRepo(SupabaseClient(
              'http://localhost',
              'anon',
              authOptions: const AuthClientOptions(autoRefreshToken: false),
            )),
          ),
          currentUserProvider.overrideWith((ref) => User(
                id: 'ich',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          fantasyAufstellungsRundeProvider.overrideWith((ref) async => 1),
          leagueRosterProvider.overrideWith((ref, id) => Stream.value([
                for (final p in pool)
                  RosterEntry(
                      managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
              ])),
          leagueLineupsProvider.overrideWith((ref, id) => Stream.value([
                FantasyLineup(
                  managerId: 'ich',
                  round: 1,
                  // Zehn statt elf: Ein leerer Platz gehört ins Bild, er ist
                  // ein eigener Zustand („frei", Einladung statt Fehler).
                  playerIds: {for (final p in elf.take(10)) p.id},
                ),
              ])),
          roundStatsProvider.overrideWith((ref, round) async => stats),
          fantasySeasonFixturesProvider
              .overrideWith((ref) async => spiele(gelaufen: gelaufen)),
          absencesProvider.overrideWith((ref) => Stream.value({
                'd2': const PlayerAbsence(
                    playerId: 'd2',
                    gesperrt: false,
                    grundQuelle: 'Hamstring Injury'),
                'm2': const PlayerAbsence(
                    playerId: 'm2',
                    gesperrt: true,
                    grundQuelle: 'Red Card Suspension'),
              })),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: LineupEditor(league: liga)),
          ),
        ),
      );

  Future<void> zeichne(WidgetTester tester,
      {required Set<String> gelaufen}) async {
    tester.view.physicalSize = const Size(402 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(rahmen(gelaufen: gelaufen));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('Vorschau: Spielfeld, bearbeitbar', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    await zeichne(tester, gelaufen: const {});

    // Solange nichts läuft, ist die Elf zu ändern — kein Sperrband.
    expect(find.text('Aufstellung steht — alle Spiele laufen'), findsNothing);

    await expectLater(find.byType(LineupEditor),
        matchesGoldenFile('goldens/aufstellung_feld.png'));
  });

  testWidgets('Vorschau: Spielfeld, einzelne Spieler gesperrt',
      (tester) async {
    // **Der Fall eines gewöhnlichen Spieltags:** Das Freitagsspiel läuft, der
    // Rest steht noch. Hier trägt das Schloss am Wappen die Auskunft, denn es
    // ist die einzige Stelle, an der steht, *wen* es betrifft.
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    await zeichne(tester, gelaufen: const {fcb});

    expect(find.text('Aufstellung steht — alle Spiele laufen'), findsNothing);
    expect(find.textContaining('Spieler sind gesperrt'), findsOneWidget);

    await expectLater(find.byType(LineupEditor),
        matchesGoldenFile('goldens/aufstellung_feld_teilweise.png'));
  });

  testWidgets('Vorschau: Spielfeld, alles gesperrt', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    await zeichne(tester, gelaufen: const {bvb, fcb});

    // **Der wichtigste Zustand dieses Schirms**: Es geht nichts mehr, und das
    // muss man sehen, ohne es auszuprobieren.
    expect(find.text('Aufstellung steht — alle Spiele laufen'), findsOneWidget);

    await expectLater(find.byType(LineupEditor),
        matchesGoldenFile('goldens/aufstellung_feld_gesperrt.png'));
  });
}
