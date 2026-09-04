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

    // **Ein echter Samstag, keine Handvoll Spiele.** Die erste Fassung stellte
    // sieben Partien hin — damit sah der Schirm ordentlich aus, und genau das
    // war das Problem: Unübersichtlich wird er erst bei fünfzehn, wenn fünf
    // Zeilen dieselbe Uhrzeit tragen und man die laufenden Spiele suchen muss.
    // Eine Vorschau, die den ruhigen Fall zeigt, taugt nicht zur Beurteilung.
    final bl1 = [
      _fx('1', 'bundesliga', 'FC Bayern München', 'VfB Stuttgart',
          heute(15, 30), status: FixtureStatus.live, hs: 2, as: 1),
      _fx('2', 'bundesliga', 'RB Leipzig', 'Bor. Mönchengladbach',
          heute(15, 30), status: FixtureStatus.live, hs: 0, as: 0),
      _fx('3', 'bundesliga', '1. FSV Mainz 05', 'SC Paderborn 07',
          heute(15, 30), status: FixtureStatus.live, hs: 1, as: 3),
      _fx('4', 'bundesliga', 'SC Freiburg', 'TSG Hoffenheim', heute(15, 30),
          status: FixtureStatus.live, hs: 0, as: 1),
      _fx('5', 'bundesliga', 'Werder Bremen', 'FC Augsburg', heute(15, 30),
          status: FixtureStatus.live, hs: 2, as: 2),
      _fx('6', 'bundesliga', 'Union Berlin', 'Eintracht Frankfurt',
          heute(18, 30)),
    ];
    final bl2 = [
      _fx('7', 'bundesliga2', 'Hamburger SV', 'Hannover 96', heute(13, 0),
          status: FixtureStatus.finished, hs: 1, as: 1),
      _fx('8', 'bundesliga2', 'Karlsruher SC', 'SV 07 Elversberg', heute(13, 0),
          status: FixtureStatus.finished, hs: 0, as: 2),
      _fx('9', 'bundesliga2', 'Fortuna Düsseldorf', '1. FC Kaiserslautern',
          heute(13, 0), status: FixtureStatus.finished, hs: 3, as: 1),
      _fx('10', 'bundesliga2', 'VfL Bochum 1848', 'VfL Osnabrück',
          heute(20, 30)),
    ];
    final l3 = [
      _fx('11', 'liga3', 'Dynamo Dresden', 'Energie Cottbus', heute(14, 0),
          status: FixtureStatus.finished, hs: 2, as: 0),
      _fx('12', 'liga3', 'TSV 1860 München', 'Alemannia Aachen', heute(14, 0),
          status: FixtureStatus.finished, hs: 1, as: 1),
      _fx('13', 'liga3', 'FC Ingolstadt 04', 'Arminia Bielefeld',
          heute(16, 30)),
    ];
    final frauen = [
      _fx('14', 'frauen_bundesliga', 'TSG Hoffenheim W',
          'Bayer Leverkusen W', heute(16, 0)),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leagueSeasonFixturesProvider.overrideWith(
            (ref, id) async => switch (id) {
              'bundesliga' => bl1,
              'bundesliga2' => bl2,
              'liga3' => l3,
              'frauen_bundesliga' => frauen,
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

  testWidgets('Vorschau: Live-Tab am ruhigen Tag', (tester) async {
    // **Die Gegenprobe zum vollen Samstag.** Die Zeitblöcke sind für den Tag
    // gebaut, an dem fünf Partien dieselbe Uhrzeit tragen — an einem Freitag
    // mit einem Spiel je Wettbewerb bekommt jedes seinen eigenen Kopf, und
    // genau dort könnte die Ordnung zur Aufblähung werden. Ohne dieses zweite
    // Bild wäre der Fall nie angesehen worden.
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final n = DateTime.now();
    DateTime heute(int h, int m) => DateTime(n.year, n.month, n.day, h, m);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leagueSeasonFixturesProvider.overrideWith(
            (ref, id) async => switch (id) {
              'bundesliga' => [
                  _fx('r1', 'bundesliga', 'VfB Stuttgart', '1. FC Köln',
                      heute(20, 30)),
                ],
              'bundesliga2' => [
                  _fx('r2', 'bundesliga2', 'Arminia Bielefeld', 'FC St. Pauli',
                      heute(18, 30)),
                  _fx('r3', 'bundesliga2', 'Hannover 96', 'Karlsruher SC',
                      heute(18, 30)),
                ],
              'liga3' => [
                  _fx('r4', 'liga3', 'FC Ingolstadt 04', 'Alemannia Aachen',
                      heute(19, 0)),
                ],
              _ => const <Fixture>[],
            },
          ),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const LiveScreen()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // Wie beim vollen Spieltag: **nur mit `--update-goldens` vergleichen.**
    // Der Schirm baut seine Tagesleiste aus `DateTime.now()`, und die
    // Wettbewerbslogos werden geladen — ob sie im Bild stehen, hängt am
    // Zeitpunkt. Genau daran ist dieser Test beim ersten Durchlauf gescheitert
    // (0,34 % Abweichung, das fehlende Logo der 2. Bundesliga).
    if (!autoUpdateGoldenFiles) return;
    await expectLater(find.byType(LiveScreen),
        matchesGoldenFile('goldens/live_vorschau_ruhig.png'));
  });
}
