import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/club_screen.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:matchup/features/tippspiel/ui/matchday_screen.dart';

import 'support/schrift.dart';

// Vorschau der Tippkarte mit Formzeile:
//   flutter test --update-goldens test/tipp_form_vorschau_test.dart
// -> test/goldens/tipp_form.png

TeamRef _t(String id, String name) =>
    TeamRef(id: 'sportmonks:$id', name: name, shortName: name);

final _bayern = _t('503', 'FC Bayern München');
final _bvb = _t('68', 'Borussia Dortmund');
final _koeln = _t('3320', '1. FC Köln');
final _hsv = _t('2708', 'Hamburger SV');

Fixture _f(int tag, TeamRef h, TeamRef a, int? hs, int? as) => Fixture(
      id: 'sportmonks:$tag${h.id}${a.id}',
      leagueId: 'bundesliga',
      season: 2030,
      round: tag,
      roundName: '$tag. Spieltag',
      kickoff: DateTime(2030, 8, tag * 7),
      home: h,
      away: a,
      status: hs == null ? FixtureStatus.scheduled : FixtureStatus.finished,
      homeScore: hs,
      awayScore: as,
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Tippkarte zeigt die Form beider Teams und verlinkt den Verein',
      (tester) async {
    await initializeDateFormatting('de_DE');
    tester.view.physicalSize = const Size(402 * 3, 300 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final saison = [
      _f(1, _bayern, _koeln, 3, 0),
      _f(1, _bvb, _hsv, 1, 1),
      _f(2, _koeln, _bvb, 2, 1),
      _f(2, _hsv, _bayern, 0, 4),
      _f(3, _bayern, _bvb, 2, 2),
      _f(3, _hsv, _koeln, 1, 0),
      _f(4, _bvb, _bayern, 0, 1),
      _f(4, _koeln, _hsv, 3, 3),
      _f(5, _bayern, _hsv, 1, 2),
      _f(5, _bvb, _koeln, 4, 0),
      _f(6, _koeln, _bayern, 0, 2),
      _f(6, _hsv, _bvb, 1, 3),
    ];
    final spiel = Fixture(
      id: 'sportmonks:naechstes',
      leagueId: 'bundesliga',
      season: 2030,
      round: 7,
      roundName: '7. Spieltag',
      kickoff: DateTime(2030, 9, 30, 15, 30),
      home: _bayern,
      away: _bvb,
      status: FixtureStatus.scheduled,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        leagueSeasonFixturesProvider
            .overrideWith((ref, id) async => id == 'bundesliga' ? saison : []),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: RepaintBoundary(
                key: const Key('vorschau'),
                child: Container(
                  color: MatchUpColors.base,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: FixtureCard(
                    fixture: spiel,
                    dayLabel: 'Montag, 30. September',
                    zeitLabel: '15:30',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Bayern: S S U S N S → die letzten fünf: SUSNS. BVB: U N U N S S → NUNSS.
    final leisten = tester
        .widgetList<FormLeiste>(find.byType(FormLeiste))
        .map((l) => l.ergebnisse.map((e) => e.buchstabe).join())
        .toList();
    expect(leisten, ['SUSNS', 'NUNSS']);

    // Wappen und Name führen auf die Vereinsseite, mit der Liga des Spiels.
    final links = tester.widgetList<ClubLink>(find.byType(ClubLink)).toList();
    expect(links.map((l) => l.team.id),
        ['sportmonks:503', 'sportmonks:68']);
    expect(links.every((l) => l.leagueId == 'bundesliga'), isTrue);

    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byKey(const Key('vorschau')),
      matchesGoldenFile('goldens/tipp_form.png'),
    );
  });
}
