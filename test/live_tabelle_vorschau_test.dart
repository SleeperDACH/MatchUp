import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/tabellen_punkte.dart';
import 'package:matchup/core/models/models.dart';

import 'support/schrift.dart';

/// **Die Ligatabelle, während gespielt wird.**
///
/// Gewünscht: *„Bitte in den Tabellen eine LIVE-Tabelle einbauen. Dass, wenn
/// Spiele laufen, von den Teams, die gerade spielen, die Punktestände rot
/// angezeigt werden."*
///
/// Die Tabelle rechnet laufende Spiele seit jeher mit (`mergeLiveResults`) —
/// führt eine Mannschaft zur Halbzeit, stehen ihre drei Punkte schon in der
/// Spalte. **Zu sehen war das nicht:** Eine vorläufige Zahl sah aus wie eine
/// feste, und wer die Tabelle am Samstagnachmittag aufschlug, konnte nicht
/// erkennen, welche Ränge noch wackeln.

TeamRef _t(String id, String name) =>
    TeamRef(id: id, name: name, shortName: name);

StandingRow _r(int rank, String id, String name, int pkt, int sp, int diff) =>
    StandingRow(
      rank: rank,
      team: _t(id, name),
      points: pkt,
      played: sp,
      won: 0,
      draw: 0,
      lost: 0,
      goalsFor: diff > 0 ? diff : 0,
      goalsAgainst: diff < 0 ? -diff : 0,
    );

final _tabelle = [
  _r(1, 'fcb', 'FC Bayern München', 9, 3, 8),
  _r(2, 'rbl', 'RB Leipzig', 7, 3, 4),
  _r(3, 'bvb', 'Borussia Dortmund', 6, 3, 3),
  _r(4, 'sge', 'Eintracht Frankfurt', 5, 3, 1),
  _r(5, 'scf', 'SC Freiburg', 4, 3, 0),
  _r(6, 'fca', 'FC Augsburg', 3, 3, -2),
];

/// Zwei Partien laufen: Bayern gegen Leipzig, Freiburg gegen Augsburg.
final _laufend = laufendeTeams([
  Fixture(
    id: 'sportmonks:1',
    leagueId: 'bundesliga',
    season: 2026,
    round: 3,
    roundName: '3. Spieltag',
    kickoff: DateTime(2026, 9, 5, 15, 30),
    home: _t('fcb', 'FC Bayern München'),
    away: _t('rbl', 'RB Leipzig'),
    status: FixtureStatus.live,
    homeScore: 1,
    awayScore: 0,
  ),
  Fixture(
    id: 'sportmonks:2',
    leagueId: 'bundesliga',
    season: 2026,
    round: 3,
    roundName: '3. Spieltag',
    kickoff: DateTime(2026, 9, 5, 15, 30),
    home: _t('scf', 'SC Freiburg'),
    away: _t('fca', 'FC Augsburg'),
    status: FixtureStatus.live,
    homeScore: 2,
    awayScore: 2,
  ),
  // Ein beendetes Spiel darf **nicht** rot werden.
  Fixture(
    id: 'sportmonks:3',
    leagueId: 'bundesliga',
    season: 2026,
    round: 3,
    roundName: '3. Spieltag',
    kickoff: DateTime(2026, 9, 4, 20, 30),
    home: _t('bvb', 'Borussia Dortmund'),
    away: _t('sge', 'Eintracht Frankfurt'),
    status: FixtureStatus.finished,
    homeScore: 2,
    awayScore: 1,
  ),
]);

Widget _zeile(StandingRow r, bool live) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 24,
              child: Text('${r.rank}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Expanded(child: Text(r.team.name, maxLines: 1)),
          SizedBox(
              width: 30,
              child: Text('${r.played}', textAlign: TextAlign.center)),
          SizedBox(
              width: 34, child: TabellenPunkte(punkte: r.points, live: live)),
        ],
      ),
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Tabelle während laufender Spiele', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 420 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: MatchUpColors.base,
        body: ListView(
          children: [
            for (final r in _tabelle) _zeile(r, _laufend.contains(r.team.id)),
          ],
        ),
      ),
    ));
    await tester.pump();

    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/live_tabelle.png'));
  });

  test('nur laufende Mannschaften zählen', () {
    // **Vier Mannschaften, nicht sechs.** Ein beendetes Spiel färbt nichts —
    // seine Punkte stehen fest, und Rot heißt in dieser App „läuft gerade",
    // nicht „hat heute gespielt".
    expect(_laufend, {'fcb', 'rbl', 'scf', 'fca'});
    expect(_laufend.contains('bvb'), isFalse);
    expect(_laufend.contains('sge'), isFalse);
  });

  testWidgets('ohne laufendes Spiel ist keine Zahl rot', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [for (final r in _tabelle) _zeile(r, false)]),
      ),
    ));
    await tester.pump();

    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      expect(w.style?.color, isNot(MatchUpColors.red),
          reason: 'an einem spielfreien Tag ist die Tabelle einfarbig');
    }
  });
}
