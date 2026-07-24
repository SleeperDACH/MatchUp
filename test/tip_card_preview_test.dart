import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meine_app/core/data/odds/match_odds.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/tippspiel/ui/matchday_screen.dart';

// Vorschau der neuen Spielkarte (kein Regressionstest):
//   flutter test --update-goldens test/tip_card_preview_test.dart
// -> test/goldens/tip_card_preview.png

Fixture _fx(String id, String home, String away, DateTime ko,
        {FixtureStatus status = FixtureStatus.scheduled, int? hs, int? as}) =>
    Fixture(
      id: id,
      leagueId: 'bl1',
      season: 2025,
      round: 1,
      roundName: 'Spieltag 1',
      kickoff: ko,
      home: TeamRef(id: 'h$id', name: home, shortName: home),
      away: TeamRef(id: 'a$id', name: away, shortName: away),
      status: status,
      homeScore: hs,
      awayScore: as,
    );

MatchOdds _odds(double h, double d, double a) => MatchOdds(
      homeTeam: 'H',
      awayTeam: 'A',
      commenceTime: DateTime(2030),
      homeWin: h,
      draw: d,
      awayWin: a,
      bookmaker: 'test',
    );

void main() {
  testWidgets('Vorschau: neue Spielkarte (Zeit oben, Tippfelder, Quoten)',
      (tester) async {
    await initializeDateFormatting('de_DE');
    final future = DateTime(2030, 9, 13, 15, 30);
    final future2 = DateTime(2030, 9, 13, 18, 30);
    final past = DateTime(2020, 9, 14, 17, 30);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF12141C),
            body: Center(
              child: SizedBox(
                width: 380,
                child: RepaintBoundary(
                  key: const Key('preview'),
                  child: Container(
                    color: const Color(0xFF12141C),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FixtureCard(
                          fixture: _fx('1', 'Bayern', 'Dortmund', future),
                          odds: _odds(1.90, 3.40, 4.20),
                          dayLabel: 'Samstag, 13. September',
                        ),
                        FixtureCard(
                          fixture: _fx('2', 'Leipzig', 'Union Berlin', future2),
                          odds: _odds(1.65, 3.90, 5.10),
                        ),
                        FixtureCard(
                          fixture: _fx('3', 'Freiburg', 'Mainz', past,
                              status: FixtureStatus.finished, hs: 2, as: 1),
                          dayLabel: 'Sonntag, 14. September',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/tip_card_preview.png'));
  });
}
