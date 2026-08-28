import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/fantasy/ui/matchup_hero.dart';

import 'support/schrift.dart';

/// Vorschau des **MatchUp-Banners** in allen vier Zuständen.
///
/// `MatchupBanner` bekommt seine Daten explizit übergeben (der Provider-Teil
/// steckt in `MatchupHero`) — dadurch lässt sich der Schirm ohne einen
/// einzigen Provider zeigen. Auf dem Gerät sieht man immer nur den einen
/// Zustand, den die eigene Liga gerade hat.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: MatchUp-Banner', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Widget banner(String titel, Widget w) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titel,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              w,
            ],
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              banner(
                'VOR DEM SPIELTAG',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 0,
                  awayPoints: 0,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: false,
                  mine: true,
                  onTap: () {},
                ),
              ),
              banner(
                'LIVE',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 48.4,
                  awayPoints: 51.2,
                  homeMe: true,
                  awayMe: false,
                  live: true,
                  started: true,
                  mine: true,
                  onTap: () {},
                ),
              ),
              banner(
                'BEENDET',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 92,
                  awayPoints: 78.5,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: true,
                  mine: true,
                  onTap: () {},
                ),
              ),
              banner(
                'SPIELFREI',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: null,
                  homePoints: 0,
                  awayPoints: 0,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: false,
                  mine: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(ListView),
      matchesGoldenFile('goldens/matchup_banner_vorschau.png'),
    );
  });
}
