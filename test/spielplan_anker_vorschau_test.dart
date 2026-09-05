import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/team_fixture_list.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';

import 'support/schrift.dart';

/// Vorschau der **Spielplan-Ansicht** — kein Regressionstest:
///   flutter test --update-goldens test/spielplan_anker_vorschau_test.dart
///   -> test/goldens/spielplan_ruhe.png · spielplan_griff.png ·
///      spielplan_offen.png
///
/// **Drei Bilder, weil der Schirm zwei Zustände hat, die sich nie gleichzeitig
/// zeigen.** Im Ruhezustand steht die Trennstelle ganz oben; der Griff „Vorherige
/// Spiele anzeigen" liegt darüber und ist damit außer Sicht — ein Bild vom
/// Ruhezustand kann ihn gar nicht zeigen. Deshalb zieht die zweite Aufnahme
/// die Liste nach oben und klappt auf: nur dort ist zu beurteilen, ob der
/// Griff leise genug und die Reihenfolge lesbar ist.
///
/// Der Bildvergleich läuft nur mit `--update-goldens`: Die Spiele liegen
/// relativ zu heute, das Bild trüge sonst jeden Tag ein anderes Datum.

TeamFixture _f(String heim, String gast, DateTime anstoss, {int? tore}) =>
    TeamFixture(
      id: 'sportmonks:$heim$gast',
      kickoff: anstoss,
      status: tore == null ? FixtureStatus.scheduled : FixtureStatus.finished,
      leagueName: 'Bundesliga',
      round: 5,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: gast, name: gast, shortName: gast),
      homeScore: tore,
      awayScore: tore == null ? null : 1,
    );

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Vorschau: Spielplan', (tester) async {
    if (!autoUpdateGoldenFiles) return;

    final heute = DateTime.now();
    DateTime tage(int d) =>
        DateTime(heute.year, heute.month, heute.day + d, 15, 30);

    final fixtures = <TeamFixture>[
      _f('FC Bayern München', 'VfB Stuttgart', tage(-28), tore: 3),
      _f('SC Freiburg', 'FC Bayern München', tage(-21), tore: 0),
      _f('FC Bayern München', 'Borussia Dortmund', tage(-14), tore: 2),
      _f('1. FC Köln', 'FC Bayern München', tage(-7), tore: 1),
      _f('FC Bayern München', 'Werder Bremen', tage(3)),
      _f('RB Leipzig', 'FC Bayern München', tage(10)),
      _f('FC Bayern München', 'Bayer Leverkusen', tage(17)),
    ];

    tester.view.physicalSize = const Size(402 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SpielplanAnsicht(fixtures: fixtures)),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/spielplan_ruhe.png'),
    );

    // Nach oben ziehen, aufklappen, weiter nach oben — der Zustand, den man
    // sonst nur mit dem Daumen findet.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/spielplan_griff.png'),
    );

    await tester.tap(find.text('Vorherige Spiele anzeigen'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 260));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/spielplan_offen.png'),
    );
  });
}
