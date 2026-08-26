import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/live_screen.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/tippspiel/providers.dart';

import 'support/schrift.dart';

/// Vorschau des **Live-Tabs** — kein Regressionstest:
///   flutter test --update-goldens test/live_vorschau_test.dart
///   -> test/goldens/live_vorschau.png
///
/// Wie beim Startbildschirm gilt: Der eigene Testaccount zeigt nur, was gerade
/// zufällig ansteht — an einem spielfreien Mittwoch also einen leeren Schirm.
/// Der Live-Tab lebt aber genau von dem, was an einem vollen Spieltag
/// passiert: mehrere Wettbewerbe, laufende und beendete Spiele nebeneinander.
/// Das steht hier deshalb im Test.
///
/// Der Schirm wählt beim Öffnen **heute**; die Spiele bekommen darum das
/// aktuelle Datum mit festen Uhrzeiten.
/// **Der Bildvergleich läuft nur mit `--update-goldens`.** Das Bild zeigt den
/// heutigen Tag ("Donnerstag, 27. Aug."), weil beide Schirme intern
/// `DateTime.now()` benutzen — der Live-Tab wählt beim Öffnen heute, die
/// Kopfkarte schreibt das Datum ihres Spiels hin. Ein fest eingecheckter
/// Vergleich wäre damit **jeden Tag rot**, und ein Test, der täglich rot ist,
/// bringt niemandem etwas außer der Gewohnheit, ihn zu übergehen. Die Vorschau
/// ist zum Ansehen da; was wirklich gehalten werden muss, steht als Messung
/// daneben.
Fixture _fx(
  String id,
  String liga,
  String heim,
  String ausw,
  DateTime anstoss, {
  FixtureStatus status = FixtureStatus.scheduled,
  int? hs,
  int? as,
}) => Fixture(
  id: id,
  leagueId: liga,
  season: 2026,
  round: 3,
  roundName: '3. Spieltag',
  kickoff: anstoss,
  home: TeamRef(id: 'h$id', name: heim, shortName: heim),
  away: TeamRef(id: 'a$id', name: ausw, shortName: ausw),
  status: status,
  homeScore: hs,
  awayScore: as,
);

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Vorschau: Live-Tab am vollen Spieltag', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final n = DateTime.now();
    DateTime heute(int h, int m) => DateTime(n.year, n.month, n.day, h, m);

    final bl1 = [
      _fx(
        '1',
        'bundesliga',
        'FC Bayern München',
        'VfB Stuttgart',
        heute(15, 30),
        status: FixtureStatus.live,
        hs: 2,
        as: 1,
      ),
      _fx(
        '2',
        'bundesliga',
        'RB Leipzig',
        'Bor. Mönchengladbach',
        heute(15, 30),
        status: FixtureStatus.live,
        hs: 0,
        as: 0,
      ),
      _fx(
        '3',
        'bundesliga',
        '1. FSV Mainz 05',
        'SC Paderborn 07',
        heute(15, 30),
        status: FixtureStatus.finished,
        hs: 3,
        as: 2,
      ),
      _fx('4', 'bundesliga', 'Union Berlin', 'Eintracht Frankfurt', heute(18, 30)),
    ];
    final bl2 = [
      _fx(
        '5',
        'bundesliga2',
        'Hamburger SV',
        'Hannover 96',
        heute(13, 0),
        status: FixtureStatus.finished,
        hs: 1,
        as: 1,
      ),
      _fx('6', 'bundesliga2', 'VfL Bochum 1848', 'VfL Osnabrück', heute(20, 30)),
    ];
    final l3 = [
      _fx('7', 'liga3', 'Dynamo Dresden', 'Energie Cottbus', heute(16, 30)),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leagueSeasonFixturesProvider.overrideWith(
            (ref, id) async => switch (id) {
              'bundesliga' => bl1,
              'bundesliga2' => bl2,
              'liga3' => l3,
              _ => const <Fixture>[],
            },
          ),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const LiveScreen()),
      ),
    );
    // Kein `pumpAndSettle`: Der Live-Punkt pulsiert endlos.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(LiveScreen),
      matchesGoldenFile('goldens/live_vorschau.png'),
    );
  });
}
