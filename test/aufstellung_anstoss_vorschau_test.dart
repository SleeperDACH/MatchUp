import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **Punktebox vor und nach dem Anpfiff**.
///
/// Gemeldet: „Statt ‚–' möchte ich das nächste Spiel sehen: ‚FCB Sa 15:30'.
/// Die Größe der Box soll so bleiben. Erst wenn das jeweilige Spiel angepfiffen
/// wird, kommt die Punkteanzeige." Genau das ist hier nebeneinander zu sehen —
/// auf dem Gerät gibt es die beiden Zustände nie gleichzeitig.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998, 6, 1),
      nationality: 'DE',
    );

Fixture _f(String heim, String aus, DateTime anpfiff) => Fixture(
  id: 'sportmonks:$heim',
  leagueId: 'bundesliga',
  season: 2026,
  round: 2,
  roundName: 'Spieltag 2',
  kickoff: anpfiff,
  home: TeamRef(id: heim, name: heim, shortName: heim),
  away: TeamRef(id: aus, name: aus, shortName: aus),
  status: FixtureStatus.scheduled,
);

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Anstoß statt Strich', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 620 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // **Feste Zeitpunkte, keine relativen.** Der Schirm rechnet mit
    // `DateTime.now()`; stünden die Anpfiffe relativ dazu, trüge das Bild bei
    // jedem Lauf einen anderen Wochentag, und ein fest eingecheckter
    // Vergleich wäre täglich rot.
    final spiele = [
      // Lange vorbei → Punkte.
      _f('FC Bayern München', 'Borussia Dortmund',
          DateTime(2020, 9, 12, 15, 30)),
      // Weit in der Zukunft → Anstoß-Hinweis, und zwar immer derselbe.
      _f('SV Werder Bremen', '1. FSV Mainz 05', DateTime(2030, 9, 14, 15, 30)),
    ];

    final heim = [
      _p('h1', 'Manuel Neuer', PlayerPosition.gk, 'FC Bayern München'),
      _p('h2', 'Nico Schlotterbeck', PlayerPosition.def, 'Borussia Dortmund'),
      _p('h3', 'Marco Grüll', PlayerPosition.mid, 'SV Werder Bremen'),
      _p('h4', 'Jonathan Burkardt', PlayerPosition.fwd, '1. FSV Mainz 05'),
    ];
    final gast = [
      _p('a1', 'Gregor Kobel', PlayerPosition.gk, 'Borussia Dortmund'),
      _p('a2', 'Dayot Upamecano', PlayerPosition.def, 'FC Bayern München'),
      _p('a3', 'Nadiem Amiri', PlayerPosition.mid, '1. FSV Mainz 05'),
      _p('a4', 'Paris Brunner', PlayerPosition.fwd, 'AS Monaco'),
    ];

    MatchupSideData seite(List<FantasyPlayer> elf, Map<String, double> pkt) =>
        MatchupSideData(elf, const [], pkt, 0, const {});

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
      tipEnabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) => User(
              id: 'ich',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            ),
          ),
          clubIconsProvider.overrideWith((ref) async => const {}),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            // **Mit ausdrücklichem Grund.** Der Teilbaum malt selbst keinen;
            // im Golden wäre er sonst weiß — derselbe Fehler wie bei der
            // `ListTile`-Vorschau im Tippspiel.
            body: ColoredBox(
              key: const Key('vorschau'),
              color: const Color(0xFF12141C),
              child: SingleChildScrollView(
                child: MatchupLineups(
                  league: liga,
                  runde: 2,
                  home: seite(heim, {'h1': 12.5, 'h2': -4}),
                  away: seite(gast, {'a1': 24, 'a2': 8.5}),
                  homeId: 'ich',
                  awayId: 'anderer',
                  homeName: 'SFV03',
                  awayName: 'JojoAcz44',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byKey(const Key('vorschau')),
      matchesGoldenFile('goldens/aufstellung_anstoss.png'),
    );
  });
}
