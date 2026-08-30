import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
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
  'SFV03', 'JojoAcz44', 'ana', 'Majusch', 'tamara', 'Eric', 'Marc',
  'Benni030', 'lennartruepke', 'Leonardo', 'Spitzenreiter04', 'Schulle8',
  'julius_eggy', 'hollmannleonard', 'anhm05', 'Kevin', 'Lars', 'Tobi',
];

Widget _rahmen() {
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
      pool.add(FantasyPlayer(
        id: id,
        name: 'Spieler $m-$i',
        position: pos,
        club: 'FC Test',
        birthDate: DateTime(1999),
        nationality: 'DE',
      ));
      roster.add(
          RosterEntry(managerId: 'm$m', playerId: id, acquiredVia: 'draft'));
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
      currentUserProvider.overrideWith((ref) => User(
            id: 'm0',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: DateTime(2026).toIso8601String(),
          )),
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
      home: Scaffold(body: MatchupsBody(league: liga)),
    ),
  );
}

int _seite(WidgetTester t) =>
    (t.widget<PageView>(find.byType(PageView)).controller!.page ?? 0).round();

Future<void> _aufbauen(WidgetTester tester, {required double hoehe}) async {
  final vorher = AppConfig.supabaseInitialized;
  AppConfig.supabaseInitialized = true;
  addTearDown(() => AppConfig.supabaseInitialized = vorher);

  tester.view.physicalSize = Size(402 * 3, hoehe * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_rahmen());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(ladeSchrift);

  testWidgets('nach Wegscrollen und Zurückscrollen steht dieselbe Paarung',
      (tester) async {
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
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(_seite(tester), start + 2, reason: 'Das Wischen muss ankommen');

    final liste = find.byType(ListView).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(liste, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(find.byType(PageView), findsNothing,
        reason: 'Vorbedingung: Das Karussell muss abgebaut worden sein');

    for (var i = 0; i < 9; i++) {
      await tester.drag(liste, const Offset(0, 400));
      await tester.pumpAndSettle();
    }

    expect(_seite(tester), start + 2,
        reason: 'Nach dem Zurückscrollen muss dieselbe Paarung stehen');
  });

  testWidgets('nach einem Nachladen bleibt man auf demselben MatchUp',
      (tester) async {
    // Der zweite Weg zum selben Fehler: Ein früher `return` auf `isLoading`
    // ersetzt den ganzen Teilbaum. Der Spielerpool wird nachgeladen, sobald
    // ein Profil aufgeht.
    await _aufbauen(tester, hoehe: 900);

    final start = _seite(tester);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(_seite(tester), start + 1);

    ProviderScope.containerOf(tester.element(find.byType(MatchupsBody)))
        .invalidate(playerPoolProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget,
        reason: 'Der PageView darf beim Nachladen nicht abgebaut werden');
    expect(_seite(tester), start + 1);
  });
}
