import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';
import 'package:matchup/features/fantasy/ui/matchups_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// **Das Karussell muss stehen bleiben, wo man ist.**
///
/// Gemeldet: „Ich gehe auf das dritte MatchUp, dann runter auf ein
/// Spielerprofil, wieder hoch — der Strich ist noch auf dem dritten, angezeigt
/// wird aber das erste. Wische ich weiter, komme ich zum zweiten."
///
/// Genau diese Beschreibung nennt die Ursache: Der Punkt unter dem Karussell
/// hängt an `_bannerPage` im State und blieb richtig, **der `PageView` selbst**
/// begann wieder bei `initialPage`. Sein Zustand lebt nicht im State, sondern
/// in der Scroll-Position — und die stirbt, wenn das Widget aus dem Sichtfeld
/// scrollt und abgebaut wird.
const _namen = [
  'SFV03',
  'JojoAcz44',
  'ana',
  'Majusch',
  'tamara',
  'Eric',
  'Marc',
  'Benni030',
  'lennartruepke',
  'Leonardo',
  'Spitzenreiter04',
  'Schulle8',
  'julius_eggy',
  'hollmannleonard',
  'anhm05',
  'Kevin',
  'Lars',
  'Tobi',
];

Widget _rahmen({bool mitReitern = false}) {
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
    maxTeams: 18,
    tipEnabled: true,
  );
  final manager = [
    for (var i = 0; i < _namen.length; i++)
      FantasyManager(userId: 'm$i', username: _namen[i], draftPosition: i + 1),
  ];

  // **Echte Kader, damit die Liste echt lang wird.** Unter dem Karussell
  // stehen die Aufstellungen der gewischten Paarung — mit leeren Kadern ist
  // die Liste nur 33 Punkte länger als das Fenster, und das Karussell fällt
  // gar nicht erst aus dem Vorrat des `ListView`. Genau deshalb trifft der
  // Fehler auf dem Gerät zu: Dort stehen dort zwei mal elf Spieler.
  final pool = <FantasyPlayer>[];
  final roster = <RosterEntry>[];
  for (var m = 0; m < _namen.length; m++) {
    for (var i = 0; i < 11; i++) {
      final pos = i == 0
          ? PlayerPosition.gk
          : i < 5
          ? PlayerPosition.def
          : i < 9
          ? PlayerPosition.mid
          : PlayerPosition.fwd;
      final id = 'm$m-p$i';
      pool.add(
        FantasyPlayer(
          id: id,
          name: 'Spieler $m-$i',
          position: pos,
          club: 'FC Test',
          birthDate: DateTime(1999),
          nationality: 'DE',
        ),
      );
      roster.add(
        RosterEntry(managerId: 'm$m', playerId: id, acquiredVia: 'draft'),
      );
    }
  }
  final lineups = [
    for (var m = 0; m < _namen.length; m++)
      FantasyLineup(
        managerId: 'm$m',
        round: 1,
        playerIds: {for (var i = 0; i < 11; i++) 'm$m-p$i'},
      ),
  ];
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => User(
          id: 'm0',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime(2026).toIso8601String(),
        ),
      ),
      fantasyManagersProvider.overrideWith((ref, id) => Stream.value(manager)),
      playerPoolProvider.overrideWith((ref) async => pool),
      leagueRosterProvider.overrideWith((ref, id) => Stream.value(roster)),
      leagueLineupsProvider.overrideWith((ref, id) => Stream.value(lineups)),
      clubIconsProvider.overrideWith((ref) async => const {}),
      seasonStatsProvider.overrideWith((ref) async => const {}),
      roundStatsProvider.overrideWith((ref, r) async => const {}),
      fantasySeasonFixturesProvider.overrideWith((ref) async => const []),
      fantasyCurrentRoundProvider.overrideWith((ref) async => 1),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: mitReitern
          // Der echte Einbauort: vier Reiter, das Karussell im zweiten.
          ? DefaultTabController(
              length: 4,
              initialIndex: 1,
              child: Scaffold(
                appBar: AppBar(
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: 'Übersicht'),
                      Tab(text: 'MatchUp'),
                      Tab(text: 'Kader'),
                      Tab(text: 'Tabelle'),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    const Center(child: Text('Übersicht')),
                    MatchupsBody(league: liga),
                    const Center(child: Text('Kader')),
                    const Center(child: Text('Tabelle')),
                  ],
                ),
              ),
            )
          : Scaffold(body: MatchupsBody(league: liga)),
    ),
  );
}

/// Das Karussell — **nicht** der `PageView`, den `TabBarView` selbst benutzt.
/// Im Reiter-Aufbau gibt es beide, und der der Reiterleiste liegt darüber.
final _karussell = find.descendant(
  of: find.byType(MatchupsBody),
  matching: find.byType(PageView),
);

/// **Was unter dem Karussell steht**, also die Paarung, deren Aufstellungen
/// gezeigt werden. Sie haengt an `_bannerPage` im State — nicht an der
/// Wischposition. Genau hier faellt auseinander, was zusammengehoert.
String _darunter(WidgetTester t) {
  final w = t.widget<MatchupLineups>(find.byType(MatchupLineups));
  return '${w.homeName} : ${w.awayName}';
}

int _seite(WidgetTester t) =>
    (t.widget<PageView>(_karussell).controller!.page ?? 0).round();

Future<void> _aufbauen(
  WidgetTester tester, {
  required double hoehe,
  bool mitReitern = false,
}) async {
  final vorher = AppConfig.supabaseInitialized;
  AppConfig.supabaseInitialized = true;
  addTearDown(() => AppConfig.supabaseInitialized = vorher);

  tester.view.physicalSize = Size(402 * 3, hoehe * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_rahmen(mitReitern: mitReitern));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(ladeSchrift);

  testWidgets('nach Wegscrollen und Zurückscrollen steht dieselbe Paarung', (
    tester,
  ) async {
    // **Der gemeldete Fall, echt nachgestellt.** Das Karussell sitzt in einem
    // gewöhnlichen `ListView`; darunter stehen die Aufstellungen der
    // gewischten Paarung. Scrollt man dorthin, verlässt das Karussell den
    // 250-Punkte-Vorrat des `ListView` und wird abgebaut — beim
    // Zurückscrollen entsteht eine neue Scroll-Position.
    //
    // Ohne `PageStorageKey` beginnt die bei `initialPage`: Der Punkt darunter
    // blieb auf dem dritten MatchUp (er hängt an `_bannerPage` im State), die
    // Karte sprang auf das erste, und ein Wisch nach rechts führte zum
    // zweiten statt zum vierten.
    await _aufbauen(tester, hoehe: 480);

    final start = _seite(tester);
    await tester.drag(_karussell, const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.drag(_karussell, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(_seite(tester), start + 2, reason: 'Das Wischen muss ankommen');
    final paarung = _darunter(tester);

    final liste = find.byType(ListView).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(liste, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(
      _karussell,
      findsNothing,
      reason: 'Vorbedingung: Das Karussell muss abgebaut worden sein',
    );

    for (var i = 0; i < 9; i++) {
      await tester.drag(liste, const Offset(0, 400));
      await tester.pumpAndSettle();
    }

    expect(
      _seite(tester),
      start + 2,
      reason: 'Nach dem Zurückscrollen muss dieselbe Karte oben stehen',
    );
    expect(
      _darunter(tester),
      paarung,
      reason: 'Und dieselbe Paarung darunter — die beiden gehören zusammen',
    );
  });

  testWidgets('nach einem Nachladen bleibt man auf demselben MatchUp', (
    tester,
  ) async {
    // Der zweite Weg zum selben Fehler: Ein früher `return` auf `isLoading`
    // ersetzt den ganzen Teilbaum. Der Spielerpool wird nachgeladen, sobald
    // ein Profil aufgeht.
    await _aufbauen(tester, hoehe: 900);

    final start = _seite(tester);
    await tester.drag(_karussell, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(_seite(tester), start + 1);
    final paarung2 = _darunter(tester);

    ProviderScope.containerOf(
      tester.element(find.byType(MatchupsBody)),
    ).invalidate(playerPoolProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      _karussell,
      findsOneWidget,
      reason: 'Der PageView darf beim Nachladen nicht abgebaut werden',
    );
    expect(_seite(tester), start + 1);
    expect(_darunter(tester), paarung2);
  });

  // Beide Nachbarreiter, weil beide gemeldet wurden. Der Unterschied ist
  // nicht kosmetisch: `TabBarView` haelt den **Nachbarn** (Kader) am Leben,
  // die Tabelle liegt zwei Schritte weg und baut den Reiter ab. Ein Merker,
  // der nur einen der beiden Faelle uebersteht, faellt hier auf.
  for (final ziel in ['Kader', 'Tabelle']) {
    testWidgets('nach einem Ausflug in „$ziel" steht dieselbe Paarung', (
      tester,
    ) async {
      // **Der dritte Weg zum selben Fehler**, und der letzte: „Wenn man den Tab
      // wechselt und zurück auf den MatchUp-Tab geht, landet man wieder beim
      // ersten MatchUp."
      //
      // `TabBarView` hält nur die Nachbarn am Leben. Vom MatchUp-Reiter (1) auf
      // die Tabelle (3) ist der Weg zu weit — der ganze Teilbaum wird abgebaut,
      // und mit ihm der State, in dem `_bannerPage` liegt.
      await _aufbauen(tester, hoehe: 900, mitReitern: true);

      final start = _seite(tester);
      await tester.drag(_karussell, const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.drag(_karussell, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(_seite(tester), start + 2, reason: 'Das Wischen muss ankommen');
      final paarung = _darunter(tester);

      await tester.tap(find.text(ziel));
      await tester.pumpAndSettle();
      if (ziel == 'Tabelle') {
        expect(
          find.byType(MatchupsBody),
          findsNothing,
          reason: 'Vorbedingung: Der Reiter muss wirklich abgebaut worden sein',
        );
      }

      await tester.tap(find.text('MatchUp'));
      await tester.pumpAndSettle();

      expect(
        _seite(tester),
        start + 2,
        reason: 'Zurück im Reiter muss dieselbe Karte oben stehen',
      );
      // **Der eigentliche Fehler.** Die Karte oben ueberlebte schon, weil ihre
      // Position im `PageStorage` liegt. Die Aufstellungen darunter haengen
      // dagegen an `_bannerPage` im State — und der stirbt mit dem Reiter. Auf
      // dem Geraet sah es deshalb so aus: oben das dritte MatchUp, darunter
      // wieder das eigene, und gemeldet wurde Letzteres.
      expect(
        _darunter(tester),
        paarung,
        reason: 'Zurück im Reiter muss dieselbe Paarung darunter stehen',
      );
    });
  }
}
