import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/team_fixture_list.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';

import 'support/schrift.dart';

/// **Je Anstoßzeit ein Kopf, nicht je Spiel einer.**
///
/// Gemeldet an der Liga-Übersicht: *„Beim Spieltag bitte die gleichen
/// Spielzeiten alle in eine Box packen. Das ist anstrengend, wenn du immer das
/// Datum dazwischen hast."*
///
/// Die Ursache war eine Schleife, die `lastDay` zwar mitrechnete, aber nie
/// benutzte — beide Zweige ihres `if` taten dasselbe, und der Kopf wurde
/// **immer** ausgegeben. In einer Vereinsliste fiel das nie auf, weil dort je
/// Datum ohnehin nur eine Partie steht. Auf einem vollen Spieltag standen
/// damit neun Köpfe über neun Spielen, fünf davon Wort für Wort gleich.

TeamFixture _f(String id, String heim, String gast, DateTime anstoss,
        {int? hs, int? as}) =>
    TeamFixture(
      id: id,
      leagueName: 'Bundesliga',
      round: 2,
      kickoff: anstoss,
      home: TeamRef(id: 'h$id', name: heim, shortName: heim),
      away: TeamRef(id: 'a$id', name: gast, shortName: gast),
      status: hs == null ? FixtureStatus.scheduled : FixtureStatus.finished,
      homeScore: hs,
      awayScore: as,
    );

/// Ein echter Samstag: fünf Partien um 15:30, eine um 18:30, dazu Freitag.
List<TeamFixture> _spieltag() => [
      _f('1', 'VfB Stuttgart', '1. FC Köln', DateTime(2026, 9, 4, 20, 30)),
      _f('2', 'FC Bayern München', 'RB Leipzig', DateTime(2026, 9, 5, 15, 30)),
      _f('3', 'Borussia Dortmund', 'SC Freiburg', DateTime(2026, 9, 5, 15, 30)),
      _f('4', 'Werder Bremen', 'FC Augsburg', DateTime(2026, 9, 5, 15, 30)),
      _f('5', '1. FSV Mainz 05', 'VfL Wolfsburg', DateTime(2026, 9, 5, 15, 30)),
      _f('6', 'TSG Hoffenheim', 'FC St. Pauli', DateTime(2026, 9, 5, 15, 30)),
      _f('7', 'Union Berlin', 'Eintracht Frankfurt',
          DateTime(2026, 9, 5, 18, 30)),
    ];

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('gleiche Anstoßzeiten teilen sich einen Kopf', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: MatchUpColors.base,
        body: ListView(children: fixturesWithDateHeaders(_spieltag())),
      ),
    ));
    await tester.pump();

    // Sieben Spiele, aber nur **drei** Anstoßzeiten.
    expect(find.byType(FixtureDateHeader), findsNWidgets(3),
        reason: 'je Anstoßzeit ein Kopf, nicht je Spiel einer');
    expect(find.byType(TeamFixtureCard), findsNWidgets(7));

    // Die Uhrzeit steht im Kopf …
    expect(find.text('15:30'), findsOneWidget,
        reason: 'einmal im Kopf, nicht fünfmal in den Zeilen');
    expect(find.text('20:30'), findsOneWidget);
    expect(find.text('18:30'), findsOneWidget);

    // … und der Tag genau zweimal, weil an zwei Tagen gespielt wird. Geprüft
    // wird der Wochentag, nicht die Monatsabkürzung — die kommt aus `intl`
    // und ist keine Zusicherung dieses Schirms.
    expect(find.textContaining('Fr., 4.'), findsOneWidget);
    expect(find.textContaining('Sa., 5.'), findsNWidgets(2));
  });

  testWidgets('eine Vereinsliste bleibt, wie sie war', (tester) async {
    // **Die Gegenprobe.** Dort trägt jede Partie einen eigenen Anstoß, also
    // bekommt weiter jede ihren eigenen Kopf — die Änderung darf den
    // Favoriten-Tab und die Vereinsseite nicht anfassen.
    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final einzeln = [
      _f('a', 'Hannover 96', 'Karlsruher SC', DateTime(2026, 9, 4, 18, 30)),
      _f('b', 'Hertha BSC', 'Hannover 96', DateTime(2026, 9, 12, 18, 30)),
      _f('c', 'Hannover 96', 'SV Elversberg', DateTime(2026, 9, 20, 13, 30)),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: MatchUpColors.base,
        body: ListView(children: fixturesWithDateHeaders(einzeln)),
      ),
    ));
    await tester.pump();

    expect(find.byType(FixtureDateHeader), findsNWidgets(3));
    expect(find.byType(TeamFixtureCard), findsNWidgets(3));
  });

  testWidgets('Vorschau: Spieltag in Zeitblöcken', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: MatchUpColors.base,
        body: ListView(children: fixturesWithDateHeaders(_spieltag())),
      ),
    ));
    await tester.pump();

    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/spielplan_zeitbloecke.png'));
  });
}
