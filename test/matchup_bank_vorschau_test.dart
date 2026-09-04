import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';

import 'support/schrift.dart';

/// **Die Bank steht immer da, nicht hinter einem Ausklapper.**
///
/// Gemeldet: „Die Bank beim MatchUp soll nicht durch so einen Dropdown
/// angezeigt werden, sondern immer — allerdings so, dass die Spieler so klein
/// bleiben, wie sie es jetzt sind. Also keine vollen Boxen."
///
/// Beides zusammen ist der Punkt: sichtbar **und** leise. Die große
/// Gegenüberstellung mit Wappen an den Außenkanten gehört der Startelf; würde
/// die Bank dieselbe Form bekommen, hätte der Schirm zwei gleich laute
/// Abschnitte und die Elf verlöre ihren Vorrang.

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
        _p('$p d$i', 'Robin Koch $i', PlayerPosition.def),
      for (var i = 0; i < 4; i++)
        _p('$p m$i', 'Rani Khedira $i', PlayerPosition.mid),
      for (var i = 0; i < 2; i++)
        _p('$p f$i', 'Michael Olise $i', PlayerPosition.fwd),
    ];

List<FantasyPlayer> _bank(String p) => [
      _p('${p}bgk', 'Tim Boss', PlayerPosition.gk),
      _p('${p}bd', 'Sacha Boey', PlayerPosition.def),
      _p('${p}bm', 'Aleks Pavlovic', PlayerPosition.mid),
      _p('${p}bf', 'Linton Maina', PlayerPosition.fwd),
      _p('${p}bf2', 'Igor Matanovic', PlayerPosition.fwd),
    ];

MatchupSideData _seite(String p) => MatchupSideData(
      _elf(p),
      _bank(p),
      {for (final x in [..._elf(p), ..._bank(p)]) x.id: 6.0},
      66,
      {for (final x in [..._elf(p), ..._bank(p)]) x.id},
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Bank ohne Ausklapper', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1500 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
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
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // **Ohne einen einzigen Tipp sichtbar.** Vorher lag hier eine
    // `ExpansionTile`, und die Namen der Bank standen erst nach dem Aufklappen
    // im Baum.
    expect(find.byType(ExpansionTile), findsNothing,
        reason: 'kein Ausklapper mehr');
    expect(find.text('Bank'), findsOneWidget);
    // Beide Seiten haben denselben Ersatztorwart — zweimal ist also richtig.
    expect(find.text('Boss'), findsNWidgets(2),
        reason: 'die Bankspieler stehen ohne Zutun da, je Seite einer');

    await expectLater(find.byType(MatchupLineups),
        matchesGoldenFile('goldens/matchup_bank.png'));
  });
}
