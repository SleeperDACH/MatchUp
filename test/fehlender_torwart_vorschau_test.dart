import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';

import 'support/schrift.dart';

/// **Ein Torwartplatz, den niemand besetzt, muss man sehen.**
///
/// Gemeldet am 04.09.2026, nachdem die Elf mit zehn Mann serverseitig erlaubt
/// war (Migration 0120): *„Aber dass der TW leer ist, wird nicht angezeigt."*
/// Zu Recht — in der Duell-Ansicht war die leere Zelle ein blanker
/// `SizedBox(height: 60)`, und stand auf **beiden** Seiten kein Torwart,
/// verschwand der ganze Block. Wer draufschaute, sah eine ordentliche
/// Aufstellung mit einer Reihe weniger.
///
/// Derselbe Fehler wie das leere Feld im Draft-Brett und das Phantom in der
/// Elf: **Ein Zustand „hier fehlt jemand" sah aus wie „alles in Ordnung".**
///
/// Die Vorschau stellt drei Fälle nebeneinander, weil sie sich unterscheiden
/// müssen:
///   * links ein Torwart, rechts keiner — die Lücke muss auffallen;
///   * auf beiden Seiten keiner — der Block darf nicht verschwinden;
///   * ungleiche Feldspieler-Formation — dort fehlt **nichts**, dort spielt
///     die Gegenseite bloß anders, und eine Warnung wäre schlicht falsch.

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

FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      nationality: 'de',
      birthDate: DateTime(1998, 5, 4),
    );

MatchupSideData _seite(List<FantasyPlayer> elf) => MatchupSideData(
      elf,
      const [],
      {for (final p in elf) p.id: 4.5},
      elf.length * 4.5,
      {for (final p in elf) p.id},
    );

/// Zehn Feldspieler, kein Torwart — Lewins Fall.
List<FantasyPlayer> _ohneTorwart() => [
      for (var i = 0; i < 4; i++)
        _p('d$i', 'Abwehr $i', PlayerPosition.def, 'RB Leipzig'),
      for (var i = 0; i < 4; i++)
        _p('m$i', 'Mittelfeld $i', PlayerPosition.mid, 'SC Freiburg'),
      for (var i = 0; i < 2; i++)
        _p('f$i', 'Sturm $i', PlayerPosition.fwd, 'FC Bayern München'),
    ];

/// Eine reguläre Elf, 4-4-2.
List<FantasyPlayer> _mitTorwart() => [
      _p('gk', 'Torwart', PlayerPosition.gk, 'FC Bayern München'),
      ..._ohneTorwart().map(
        (p) => _p('x${p.id}', '${p.name} B', p.position, p.club),
      ),
    ];

/// Eine 3-5-2 — andere Formation, aber nichts fehlt.
List<FantasyPlayer> _andereFormation() => [
      _p('ygk', 'Torwart Y', PlayerPosition.gk, 'VfB Stuttgart'),
      for (var i = 0; i < 3; i++)
        _p('yd$i', 'Abwehr Y$i', PlayerPosition.def, 'VfB Stuttgart'),
      for (var i = 0; i < 5; i++)
        _p('ym$i', 'Mittelfeld Y$i', PlayerPosition.mid, 'VfB Stuttgart'),
      for (var i = 0; i < 2; i++)
        _p('yf$i', 'Sturm Y$i', PlayerPosition.fwd, 'VfB Stuttgart'),
    ];

Widget _duell(MatchupSideData heim, MatchupSideData gast, String titel) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Text(
            titel.toUpperCase(),
            style: const TextStyle(
              color: MatchUpColors.snow,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 11,
            ),
          ),
        ),
        MatchupLineups(
          league: FantasyLeague(
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
          ),
          runde: 2,
          home: heim,
          away: gast,
          homeId: 'u1',
          awayId: 'u2',
          homeName: 'Lewin9',
          awayName: 'SFV03',
        ),
      ],
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: unbesetzte Torwartposition', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1700 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: MatchUpColors.base,
            body: SingleChildScrollView(
              child: Column(
                children: [
                  _duell(_seite(_ohneTorwart()), _seite(_mitTorwart()),
                      'links ohne Torwart'),
                  _duell(_seite(_ohneTorwart()), _seite(_ohneTorwart()),
                      'beide ohne Torwart'),
                  _duell(_seite(_mitTorwart()), _seite(_andereFormation()),
                      '4-4-2 gegen 3-5-2 — hier fehlt nichts'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // **Die Messungen tragen, nicht das Bild.** Zwei Seiten ohne Torwart
    // ergeben zwei Meldungen, das Duell mit vollen Elfen keine.
    expect(find.text('Kein Torwart'), findsNWidgets(3),
        reason: 'einmal links, zweimal im Duell ohne Torwart auf beiden Seiten');
    expect(find.text('Kein Abwehrspieler'), findsNothing,
        reason: 'eine andere Formation ist kein Mangel');
    expect(find.text('Kein Mittelfeldspieler'), findsNothing);

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/fehlender_torwart.png'),
    );
  });
}
