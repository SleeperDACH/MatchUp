import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/match_detail_screen.dart';
import 'package:matchup/core/models/match_detail.dart';
import 'package:matchup/core/models/models.dart';

MatchEvent _wechsel(int minute, String rein, int reinId, String raus,
        int rausId, bool heim) =>
    MatchEvent(
      minute: minute,
      type: 'Substitution',
      forHomeTeam: heim,
      player: rein,
      playerId: reinId,
      related: raus,
      relatedPlayerId: rausId,
    );

// Vorschau der Aufstellung (kein Regressionstest):
//   flutter test --update-goldens test/lineup_preview_test.dart
// -> test/goldens/lineup_pitch_preview.png
//    test/goldens/lineup_bench_preview.png
//
// Zeigt, was sich ohne laufende App schlecht prüfen lässt: Heim oben,
// Auswärts unten, Trikots in Vereinsfarben, Formation in der Seitenleiste
// und die Mannschaftszuordnung der Bank-Spalten.

TeamRef _t(String name) => TeamRef(id: 'sportmonks:1', name: name, shortName: name);

LineupPlayer _p(String name, int nr, bool heim, int row, int col,
        {bool start = true}) =>
    LineupPlayer(
      name: name,
      forHomeTeam: heim,
      starting: start,
      playerId: nr + (heim ? 0 : 100),
      number: nr,
      row: row,
      col: col,
    );

/// 4-2-3-1 bzw. 4-3-3 als Raster (Reihe 1 = Torwart).
List<LineupPlayer> _elf(bool heim, List<int> formation) {
  final out = <LineupPlayer>[_p(heim ? 'Keeper' : 'Torwart', 1, heim, 1, 1)];
  var nr = 2;
  for (var r = 0; r < formation.length; r++) {
    for (var c = 0; c < formation[r]; c++) {
      out.add(_p('Spieler $nr', nr, heim, r + 2, c + 1));
      nr++;
    }
  }
  return out;
}

void main() {
  testWidgets('Vorschau: Spielfeld — Heim oben, Auswärts unten',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF12141C),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: RepaintBoundary(
              key: const Key('pitch'),
              child: PitchLineup(
                home: _elf(true, [4, 2, 3, 1]),
                away: _elf(false, [4, 3, 3]),
                homeTeam: _t('Borussia Dortmund'),
                awayTeam: _t('FC Bayern München'),
                homeFormation: '4-2-3-1',
                awayFormation: '4-3-3',
                yellow: const {5},
                red: const {107},
                // Zwei Wechsel: Heim nimmt die 5 runter, Auswärts die 104.
                subs: Substitutions.from([
                  _wechsel(61, 'Ersatz 1', 20, 'Spieler 5', 5, true),
                  _wechsel(70, 'Reserve 1', 130, 'Spieler 4', 104, false),
                ], const []),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(find.byKey(const Key('pitch')),
        matchesGoldenFile('goldens/lineup_pitch_preview.png'));
  });

  testWidgets('Vorschau: Bank mit Mannschaftszuordnung', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF12141C),
          body: Center(
            child: SizedBox(
              width: 400,
              child: RepaintBoundary(
                key: const Key('bench'),
                child: Container(
                  color: const Color(0xFF12141C),
                  padding: const EdgeInsets.all(12),
                  child: LineupBlock(
                    title: 'Bank',
                    home: [
                      for (var i = 0; i < 4; i++)
                        _p('Ersatz ${i + 1}', 20 + i, true, 0, 0,
                            start: false)
                    ],
                    away: [
                      for (var i = 0; i < 4; i++)
                        _p('Reserve ${i + 1}', 30 + i, false, 0, 0,
                            start: false)
                    ],
                    homeTeam: _t('Borussia Dortmund'),
                    awayTeam: _t('FC Bayern München'),
                    // Je ein Eingewechselter pro Bank.
                    subs: Substitutions.from([
                      _wechsel(61, 'Ersatz 1', 20, 'Spieler 5', 5, true),
                      _wechsel(70, 'Reserve 1', 130, 'Spieler 4', 104, false),
                    ], const []),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(find.byKey(const Key('bench')),
        matchesGoldenFile('goldens/lineup_bench_preview.png'));
  });
}
