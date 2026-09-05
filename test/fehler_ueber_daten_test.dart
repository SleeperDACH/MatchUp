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
import 'package:matchup/features/fantasy/ui/matchups_screen.dart';

import 'support/schrift.dart';

/// **Ein Fehler ersetzt den Schirm nur, wenn es nichts zu zeigen gibt.**
///
/// Gemeldet: *„Wenn ich auf dem MatchUp-Tab bin, während Spiele laufen, muss
/// ich alle 3 Sekunden erneut laden, obwohl es eine Verbindung abbricht. Das
/// ist sehr, sehr anstrengend."*
///
/// `fantasyManagersProvider` ist ein Realtime-Stream. Reißt die Verbindung ab
/// — an einem Spieltag immer wieder —, meldet er einen Fehler **und liefert
/// den letzten Stand trotzdem mit**. Der Schirm schaute nur auf `hasError`
/// und tauschte den ganzen Tab gegen „Matchups konnten nicht geladen werden"
/// samt Knopf, obwohl die Daten vollständig dalagen.
///
/// Der Spinner hing schon an der richtigen Frage („sind Daten da?"), nachdem
/// er einmal das Karussell zurückgeworfen hatte. Der Fehlerzweig war beim
/// selben Umbau übersehen worden — und er hatte dieselbe Nebenwirkung: Der
/// frühe `return` baut den `PageView` ab, das Karussell fiel also mit auf das
/// erste MatchUp zurück.

const _roster = RosterConfig(
  gk: 1, def: 4, mid: 4, fwd: 2, bench: 5,
  defMin: 3, defMax: 5, midMin: 2, midMax: 5, fwdMin: 1, fwdMax: 4,
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
  createdBy: 'u1',
  maxTeams: 4,
);

FantasyManager _m(String id, String name) =>
    FantasyManager(userId: id, username: name, teamName: name);

FantasyPlayer _p(String id) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: PlayerPosition.mid,
      club: 'FC Bayern München',
      nationality: 'de',
      birthDate: DateTime(1998, 5, 4),
    );

/// Ein Stream, der erst Daten liefert und danach einen Fehler wirft — genau
/// das, was eine abreißende Realtime-Verbindung tut.
Stream<List<FantasyManager>> _erstDatenDannFehler() async* {
  yield [_m('u1', 'SFV03'), _m('u2', 'Lewin9')];
  await Future<void>.delayed(const Duration(milliseconds: 30));
  throw Exception('Realtime-Verbindung abgebrochen');
}

void main() {
  setUpAll(ladeSchrift);
  setUp(() => AppConfig.supabaseInitialized = true);
  tearDown(() => AppConfig.supabaseInitialized = false);

  testWidgets('ein Verbindungsabbruch über vorhandenen Daten ersetzt den '
      'MatchUp-Tab nicht', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        fantasyManagersProvider
            .overrideWith((ref, id) => _erstDatenDannFehler()),
        playerPoolProvider.overrideWith((ref) async => [_p('p1'), _p('p2')]),
        leagueRosterProvider
            .overrideWith((ref, id) => Stream.value(const <RosterEntry>[])),
        leagueLineupsProvider
            .overrideWith((ref, id) => Stream.value(const <FantasyLineup>[])),
        fantasySeasonFixturesProvider.overrideWith((ref) async => const []),
        roundStatsProvider.overrideWith(
            (ref, r) async => const <String, PlayerMatchStats>{}),
        seasonStatsProvider.overrideWith(
            (ref) async => const <int, Map<String, PlayerMatchStats>>{}),
        clubIconsProvider.overrideWith((ref) async => const <String, String?>{}),
        currentUserProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: MatchupsScreen(league: _liga)),
      ),
    ));

    // Erst die Daten …
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('Matchups konnten nicht geladen werden.'), findsNothing,
        reason: 'mit Daten gibt es nichts zu melden');

    // … dann der Abbruch. Der Schirm muss stehen bleiben.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Matchups konnten nicht geladen werden.'), findsNothing,
        reason: 'der letzte Stand ist besser als ein leerer Tab mit Knopf');
    expect(find.text('Erneut laden'), findsNothing);
  });

  testWidgets('ohne jede Daten meldet er den Fehler weiterhin',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        // **Die Gegenprobe.** Ohne sie hätte der Test auch dann bestanden,
        // wenn der Fehlerschirm ganz verschwunden wäre — und dann stünde bei
        // einem echten Ausfall eine leere Fläche ohne Erklärung.
        fantasyManagersProvider.overrideWith(
            (ref, id) => Stream<List<FantasyManager>>.error(Exception('weg'))),
        playerPoolProvider.overrideWith((ref) async => [_p('p1')]),
        leagueRosterProvider
            .overrideWith((ref, id) => Stream.value(const <RosterEntry>[])),
        leagueLineupsProvider
            .overrideWith((ref, id) => Stream.value(const <FantasyLineup>[])),
        fantasySeasonFixturesProvider.overrideWith((ref) async => const []),
        roundStatsProvider.overrideWith(
            (ref, r) async => const <String, PlayerMatchStats>{}),
        seasonStatsProvider.overrideWith(
            (ref) async => const <int, Map<String, PlayerMatchStats>>{}),
        clubIconsProvider.overrideWith((ref) async => const <String, String?>{}),
        currentUserProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: MatchupsScreen(league: _liga)),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Matchups konnten nicht geladen werden.'), findsOneWidget);
  });
}
