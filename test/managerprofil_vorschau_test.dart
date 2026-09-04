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
import 'package:matchup/features/fantasy/ui/manager_profile_screen.dart';

import 'support/schrift.dart';

/// Vorschau des **Ligaprofils eines Mitspielers** — kein Regressionstest:
///   flutter test --update-goldens test/managerprofil_vorschau_test.dart
///
/// **Der Schirm hatte keine Vorschau**, und genau deshalb waren drei Zustände
/// nie beurteilt worden:
///
///   * eine gestellte Elf — der Normalfall;
///   * **keine gestellte Elf**: Dort zeigte der Schirm `bestEleven`,
///     ununterscheidbar von einer echten Aufstellung. Für einen fremden
///     Manager ist das eine Behauptung über eine Entscheidung, die er nie
///     getroffen hat;
///   * eine Elf **ohne Torwart** (seit Migration 0120 möglich): Die
///     Torwartreihe rendert dann als leere Zeile, und das Feld sieht aus wie
///     eine ordentliche Aufstellung mit einer Bahn weniger.
///
/// Dazu die Regel, um die es beim Umbau ging: Das Profil liest die
/// **Aufstellungsrunde**, nicht die Anzeigerunde. Zwischen dem letzten Abpfiff
/// und der Waiver-Frist am Montag fallen die beiden auseinander, und in diesem
/// Fenster zeigte das Profil die Elf der Vorwoche — gemeldet als „das Profil
/// soll immer die aktuelle Aufstellung anzeigen".

const _roster = RosterConfig(
  gk: 1,
  def: 4,
  mid: 4,
  fwd: 2,
  bench: 5,
  defMin: 3,
  defMax: 5,
  midMin: 2,
  midMax: 5,
  fwdMin: 1,
  fwdMax: 4,
);

final _liga = FantasyLeague(
  id: 'l1',
  name: 'MatchUp! #1',
  mode: FantasyMode.liga,
  season: 2026,
  pickTime: DraftPickTime.h2,
  scoring: const FantasyScoringRules(),
  roster: _roster,
  inviteCode: 'ABC',
  draftStatus: DraftStatus.done,
  createdBy: 'chef',
  maxTeams: 18,
);

FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      nationality: 'de',
      birthDate: DateTime(1998, 5, 4),
    );

final _torhueter = [
  _p('gk1', 'Jonas Urbig', PlayerPosition.gk, 'FC Bayern München'),
  _p('gk2', 'Tim Boss', PlayerPosition.gk, 'SV 07 Elversberg'),
];

final _feldspieler = [
  _p('d1', 'Willi Orbán', PlayerPosition.def, 'RB Leipzig'),
  _p('d2', 'Robin Koch', PlayerPosition.def, 'Eintracht Frankfurt'),
  _p('d3', 'Joe Scally', PlayerPosition.def, 'Borussia Mönchengladbach'),
  _p('d4', 'Phillipp Mwene', PlayerPosition.def, '1. FSV Mainz 05'),
  _p('d5', 'Sacha Boey', PlayerPosition.def, 'FC Bayern München'),
  _p('m1', 'Rani Khedira', PlayerPosition.mid, '1. FC Union Berlin'),
  _p('m2', 'Janik Haberer', PlayerPosition.mid, '1. FC Union Berlin'),
  _p('m3', 'Max Eggestein', PlayerPosition.mid, 'SC Freiburg'),
  _p('m4', 'Woo-yeong Jeong', PlayerPosition.mid, '1. FC Union Berlin'),
  _p('m5', 'Aleks Pavlovic', PlayerPosition.mid, 'FC Bayern München'),
  _p('f1', 'Michael Olise', PlayerPosition.fwd, 'FC Bayern München'),
  _p('f2', 'Igor Matanovic', PlayerPosition.fwd, 'SC Freiburg'),
  _p('f3', 'Linton Maina', PlayerPosition.fwd, '1. FC Köln'),
];

/// Spielplan mit **drei abgepfiffenen Runden**: Damit steht die
/// Aufstellungsrunde fest auf 3 — unabhängig davon, wann der Test läuft. Ohne
/// das hinge das Bild am Kalender, und genau das ist in diesem Projekt schon
/// zweimal passiert.
List<Fixture> _spielplan() => [
      for (var r = 1; r <= 3; r++)
        for (var i = 0; i < 2; i++)
          Fixture(
            id: 'sportmonks:$r$i',
            leagueId: 'bundesliga',
            season: 2026,
            round: r,
            roundName: 'Spieltag $r',
            kickoff: DateTime(2026, 8, 7 + r * 7, 15, 30),
            home: TeamRef(id: 'h$r$i', name: 'Heim $i', shortName: 'H$i'),
            away: TeamRef(id: 'a$r$i', name: 'Gast $i', shortName: 'G$i'),
            status: r < 3 ? FixtureStatus.finished : FixtureStatus.scheduled,
            homeScore: r < 3 ? 1 : null,
            awayScore: r < 3 ? 0 : null,
          ),
    ];

Widget _rahmen({
  required List<FantasyPlayer> kader,
  required List<FantasyLineup> elfen,
}) =>
    ProviderScope(
      overrides: [
        playerPoolProvider.overrideWith((ref) async => kader),
        leagueRosterProvider.overrideWith((ref, id) => Stream.value([
              for (final p in kader)
                RosterEntry(
                  managerId: 'mgr',
                  playerId: p.id,
                  acquiredVia: 'draft',
                ),
            ])),
        leagueLineupsProvider.overrideWith((ref, id) => Stream.value(elfen)),
        fantasySeasonFixturesProvider.overrideWith((ref) async => _spielplan()),
        roundStatsProvider.overrideWith(
            (ref, r) async => const <String, PlayerMatchStats>{}),
        clubIconsProvider.overrideWith((ref) async => const <String, String?>{}),
        fantasyManagersProvider
            .overrideWith((ref, id) => Stream.value(const <FantasyManager>[])),
        // **Ohne diesen Ersatz greift der Schirm auf `Supabase.instance` zu**,
        // die es im Test nicht gibt — dieselbe Falle wie bei den
        // Fantasy-Einstellungen. `null` heißt hier „ein anderer schaut zu",
        // und genau darum geht es: Das Profil wird von jemand anderem geöffnet.
        currentUserProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: ManagerProfileScreen(
          league: _liga,
          managerId: 'mgr',
          managerName: 'Lewin9',
        ),
      ),
    );

Future<void> _zeichne(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(w);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(ladeSchrift);

  setUp(() => AppConfig.supabaseInitialized = true);
  tearDown(() => AppConfig.supabaseInitialized = false);

  testWidgets('Vorschau: gestellte Elf', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _zeichne(
      tester,
      _rahmen(
        kader: [..._torhueter, ..._feldspieler],
        elfen: [
          FantasyLineup(
            managerId: 'mgr',
            round: 3,
            playerIds: {
              'gk1', 'd1', 'd2', 'd3', 'd4', //
              'm1', 'm2', 'm3', 'm4', 'f1', 'f2',
            },
          ),
        ],
      ),
    );

    expect(find.text('Aufstellung · Spieltag 3'), findsOneWidget,
        reason: 'die Aufstellungsrunde, nicht die Anzeigerunde');
    expect(find.textContaining('Noch nicht gestellt'), findsNothing);
    await expectLater(find.byType(ManagerProfileScreen),
        matchesGoldenFile('goldens/managerprofil_gestellt.png'));
  });

  testWidgets('Vorschau: noch nicht gestellt', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _zeichne(
      tester,
      _rahmen(kader: [..._torhueter, ..._feldspieler], elfen: const []),
    );

    // **Der ganze Punkt dieses Falls.** Ohne die Zeile stünde hier eine
    // gerechnete Elf, und niemand könnte sie von einer gestellten
    // unterscheiden.
    expect(find.textContaining('Noch nicht gestellt'), findsOneWidget);
    await expectLater(find.byType(ManagerProfileScreen),
        matchesGoldenFile('goldens/managerprofil_offen.png'));
  });

  testWidgets('Vorschau: Elf ohne Torwart', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _zeichne(
      tester,
      _rahmen(
        kader: _feldspieler,
        elfen: [
          FantasyLineup(
            managerId: 'mgr',
            round: 3,
            playerIds: {
              'd1', 'd2', 'd3', 'd4', //
              'm1', 'm2', 'm3', 'm4', 'f1', 'f2',
            },
          ),
        ],
      ),
    );

    expect(find.text('Kein Torwart'), findsOneWidget,
        reason: 'eine leere Torwartreihe ist sonst gar nicht zu sehen');
    await expectLater(find.byType(ManagerProfileScreen),
        matchesGoldenFile('goldens/managerprofil_ohne_torwart.png'));
  });
}
