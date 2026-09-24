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
import 'package:matchup/features/fantasy/ui/manager_profile_screen.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// **Der Benutzername im MatchUp führt ins Ligaprofil.**
///
/// Auf Ansage: „Wenn man im MatchUp-Tab auf den Benutzernamen drückt, soll man
/// auf die Benutzerprofile kommen." Der Weg dorthin gab es längst
/// (`showManagerProfile`), erreichbar war er nur über die Tabelle — im MatchUp
/// stand der Name als toter Text.
///
/// **Ein Vergleichsbild kann das nicht prüfen:** Es zeigt, wie etwas aussah,
/// nicht wohin ein Tipp führt. Deshalb eine Zusicherung statt eines Bildes.

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
  maxTeams: 18,
);

FantasyPlayer _p(String id, String name, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: 'FC Bayern München',
      nationality: 'de',
      birthDate: DateTime(1998, 5, 4),
    );

List<FantasyPlayer> _elf(String p) => [
      _p('${p}gk', 'Jonas Urbig', PlayerPosition.gk),
      for (var i = 0; i < 4; i++)
        _p('${p}d$i', 'Robin Koch $i', PlayerPosition.def),
      for (var i = 0; i < 4; i++)
        _p('${p}m$i', 'Rani Khedira $i', PlayerPosition.mid),
      for (var i = 0; i < 2; i++)
        _p('${p}f$i', 'Michael Olise $i', PlayerPosition.fwd),
    ];

/// **Mit Bank** — ohne Bankspieler gäbe es keinen Spaltenkopf und damit nichts
/// anzutippen.
List<FantasyPlayer> _bank(String p) => [
      _p('${p}b1', 'Sacha Boey', PlayerPosition.def),
      _p('${p}b2', 'Aleks Pavlovic', PlayerPosition.mid),
    ];

MatchupSideData _seite(String p) => MatchupSideData(
      _elf(p),
      _bank(p),
      {for (final x in [..._elf(p), ..._bank(p)]) x.id: 12.0},
      132,
      {for (final x in [..._elf(p), ..._bank(p)]) x.id},
    );

final _spiele = [
  Fixture(
    id: 'sportmonks:1',
    leagueId: 'bundesliga',
    season: 2026,
    round: 2,
    roundName: 'Spieltag 2',
    kickoff: DateTime.now().subtract(const Duration(hours: 2)),
    home: const TeamRef(id: 'fcb', name: 'FC Bayern München', shortName: 'FCB'),
    away: const TeamRef(id: 'bvb', name: 'Borussia Dortmund', shortName: 'BVB'),
    status: FixtureStatus.finished,
    homeScore: 1,
    awayScore: 0,
  ),
];

Widget _rahmen() => ProviderScope(
      overrides: [
        fantasySeasonFixturesProvider.overrideWith((ref) async => _spiele),
        clubIconsProvider.overrideWith((ref) async => const {}),
        playerPoolProvider.overrideWith((ref) async => _elf('h')),
        leagueRosterProvider
            .overrideWith((ref, id) => Stream.value(const <RosterEntry>[])),
        leagueLineupsProvider
            .overrideWith((ref, id) => Stream.value(const <FantasyLineup>[])),
        fantasyManagersProvider
            .overrideWith((ref, id) => Stream.value(const <FantasyManager>[])),
        currentUserProvider.overrideWith((ref) => User(
              id: 'u1',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: MatchUpColors.base,
          body: SingleChildScrollView(
            child: MatchupLineups(
              league: _liga,
              runde: 2,
              home: _seite('h'),
              away: _seite('a'),
              homeId: 'u1',
              awayId: 'u2',
              homeName: 'SFV03',
              awayName: 'Lewin9',
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(ladeSchrift);

  setUp(() {
    // Ohne das hält sich das Profil für serverlos und zeigt statt allem eine
    // Hinweiskarte.
    AppConfig.supabaseInitialized = true;
  });

  testWidgets('Ein Tipp auf den Namen über der Bank öffnet das Ligaprofil',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_rahmen());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(ManagerProfileScreen), findsNothing,
        reason: 'Vorher steht nur das MatchUp');

    // **Getippt wird auf den sichtbaren Namen**, nicht auf eine
    // Vorlese-Beschriftung: Das ist der Weg, den ein Mensch nimmt, und er
    // hängt an keiner Eigenheit des Semantik-Baums. „Lewin9" steht im
    // Testrahmen genau einmal — über der Bankspalte des Gegners.
    //
    // **Der Gegner, nicht der eigene Name:** Beide reagieren, aber dafür ist
    // es gebaut.
    await tester.tap(find.text('Lewin9'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(ManagerProfileScreen), findsOneWidget,
        reason: 'Der Name führt ins Ligaprofil des Managers');
  });
}
