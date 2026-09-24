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
import 'package:matchup/features/fantasy/data/fantasy_league_repository.dart';
import 'package:matchup/features/fantasy/ui/ausfall_zeichen.dart';
import 'package:matchup/features/fantasy/ui/lineup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient, User;

import 'support/schrift.dart';

/// **Der Kader sagt selbst, wer ausfällt.**
///
/// Gemeldet als: *„Man muss im Kaderbereich sehen, ohne in die
/// Spieler-Karteien reinzugehen, ob ein Spieler verletzt oder gesperrt ist."*
/// Das Spielfeld zeigte es am Wappen, die Bank darunter nicht — und die Bank
/// ist die Liste, aus der man den Ersatz holt.
///
/// Geprüft wird die Bank des Aufstellungs-Editors: zwei Zeichen für zwei
/// Bankspieler, keines für die elf auf dem Feld (dort trägt das Eckzeichen am
/// Wappen die Auskunft, nicht dieses Widget).
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998, 3, 4),
      nationality: 'de',
    );

/// Ein Repository, das nichts tut — sonst greift der Editor auf
/// `Supabase.instance` zu, die es im Test nicht gibt.
class _StillesRepo extends FantasyLeagueRepository {
  _StillesRepo(super.client);

  @override
  Future<void> setLineup(String leagueId, int round, List<String> ids) async {}
}

void main() {
  setUpAll(ladeSchrift);

  const bvb = 'Borussia Dortmund';

  final elf = <FantasyPlayer>[
    _p('gk1', 'Gregor Kobel', PlayerPosition.gk, bvb),
    _p('d1', 'Nico Schlotterbeck', PlayerPosition.def, bvb),
    _p('d2', 'Waldemar Anton', PlayerPosition.def, bvb),
    _p('d3', 'Julian Ryerson', PlayerPosition.def, bvb),
    _p('d4', 'Ramy Bensebaini', PlayerPosition.def, bvb),
    _p('m1', 'Jobe Bellingham', PlayerPosition.mid, bvb),
    _p('m2', 'Felix Nmecha', PlayerPosition.mid, bvb),
    _p('m3', 'Pascal Groß', PlayerPosition.mid, bvb),
    _p('m4', 'Karim Adeyemi', PlayerPosition.mid, bvb),
    _p('f1', 'Serhou Guirassy', PlayerPosition.fwd, bvb),
    _p('f2', 'Maximilian Beier', PlayerPosition.fwd, bvb),
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

  /// Kein Spiel läuft — sonst wäre die Elf gesperrt und die Bank stumm.
  List<Fixture> spiele() {
    final jetzt = DateTime.now();
    return [
      Fixture(
        id: 'sportmonks:1',
        leagueId: 'bundesliga',
        season: 2026,
        round: 1,
        roundName: 'Spieltag 1',
        kickoff: jetzt.add(const Duration(days: 2)),
        home: const TeamRef(id: bvb, name: bvb, shortName: 'BVB'),
        away: const TeamRef(
            id: 'FC Augsburg', name: 'FC Augsburg', shortName: 'FCA'),
        status: FixtureStatus.scheduled,
      ),
    ];
  }

  Widget rahmen(Map<String, PlayerAbsence> ausfaelle) => ProviderScope(
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
                  playerIds: {for (final p in elf) p.id},
                ),
              ])),
          roundStatsProvider.overrideWith(
              (ref, round) async => const <String, PlayerMatchStats>{}),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele()),
          absencesProvider.overrideWith((ref) => Stream.value(ausfaelle)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: LineupEditor(league: liga)),
          ),
        ),
      );

  Future<SemanticsHandle> zeichne(
      WidgetTester tester, Map<String, PlayerAbsence> ausfaelle) async {
    // **Ohne diesen Griff gibt es im Test gar keinen Semantik-Baum** —
    // `find.bySemanticsLabel` fände dann auch dort nichts, wo ein Label steht,
    // und der Test hätte eine Lücke gemeldet, die es nicht gibt.
    //
    // **Geschlossen wird er im Testkörper, nicht per `addTearDown`.** Flutter
    // prüft offene Griffe, *bevor* die Aufräumer laufen; mit `addTearDown`
    // scheitert jeder Test dieser Datei, auch der, der mit Semantik nichts zu
    // tun hat.
    final semantik = tester.ensureSemantics();
    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(rahmen(ausfaelle));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return semantik;
  }

  testWidgets('Bank: verletzt und gesperrt stehen an der Karte',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    final semantik = await zeichne(tester, {
      'b2': const PlayerAbsence(
          playerId: 'b2', gesperrt: true, grundQuelle: 'Red Card Suspension'),
      'b3': const PlayerAbsence(
          playerId: 'b3', gesperrt: false, grundQuelle: 'Hamstring Injury'),
    });

    // Zwei Bankspieler, zwei Zeichen — und kein drittes für die Elf.
    expect(find.byType(AusfallZeichen), findsNWidgets(2));
    // **Die Farbe ist nicht die einzige Auskunft.** Wer sie nicht
    // unterscheidet, bekommt das Wort über die Vorlesehilfe. Gesucht wird das
    // Wort, nicht der ganze Knoten: Der Tooltip daneben trägt seinen eigenen
    // Text bei, und beide werden zu einem Knoten zusammengeführt.
    expect(find.bySemanticsLabel(RegExp('gesperrt')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('verletzt')), findsOneWidget);
    semantik.dispose();
  });

  testWidgets('Ohne Ausfall bleibt die Bank unverändert', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    final semantik = await zeichne(tester, const {});

    expect(find.byType(AusfallZeichen), findsNothing);
    // Die Bank steht trotzdem: vier Spieler, die nicht in der Elf sind.
    expect(find.text('Bank (4)'), findsOneWidget);
    semantik.dispose();
  });
}
