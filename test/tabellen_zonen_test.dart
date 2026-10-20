import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/liga_tabelle.dart';
import 'package:matchup/app/widgets/zonen_rang.dart';
import 'package:matchup/core/logic/tabellen_zonen.dart';
import 'package:matchup/core/models/models.dart';

import 'support/schrift.dart';

/// Zonen der Ligatabelle (19.10.2026): Europa nur in der Bundesliga, in der
/// 2. und 3. Liga Aufstieg, Relegation, Abstieg.
void main() {
  setUpAll(ladeSchrift);

  List<TabellenZone?> zonen(String liga, int teams) =>
      [for (var r = 1; r <= teams; r++) tabellenZone(liga, r, teams)];

  test('Bundesliga: Meister, CL, EL, Conference, Relegation, Abstieg', () {
    final z = zonen('bundesliga', 18);
    expect(z[0], TabellenZone.meister);
    expect(z.sublist(1, 4), everyElement(TabellenZone.championsLeague));
    expect(z[4], TabellenZone.europaLeague);
    expect(z[5], TabellenZone.conferenceLeague);
    expect(z.sublist(6, 15), everyElement(isNull));
    expect(z[15], TabellenZone.relegation);
    expect(z.sublist(16), everyElement(TabellenZone.abstieg));
  });

  test('2. Bundesliga: kein Europa, Aufstieg und Relegation oben', () {
    final z = zonen('bundesliga2', 18);
    expect(z, isNot(contains(TabellenZone.championsLeague)));
    expect(z, isNot(contains(TabellenZone.meister)),
        reason: 'kein Meister-Strich in der 2. Liga');
    expect(z[0], TabellenZone.aufstieg);
    expect(z[1], TabellenZone.aufstieg);
    expect(z[2], TabellenZone.relegation);
    expect(z[15], TabellenZone.relegation);
    expect(z.sublist(16), everyElement(TabellenZone.abstieg));
  });

  test('3. Liga: 20 Vereine, vier steigen ab', () {
    final z = zonen('liga3', 20);
    expect(z, isNot(contains(TabellenZone.meister)));
    expect(z[0], TabellenZone.aufstieg);
    expect(z[1], TabellenZone.aufstieg);
    expect(z[2], TabellenZone.relegation);
    expect(z.sublist(3, 16), everyElement(isNull));
    expect(z.sublist(16), everyElement(TabellenZone.abstieg));
  });

  test('Aufstieg trägt das Gold des Meisters', () {
    expect(TabellenZone.aufstieg.farbe, TabellenZone.meister.farbe);
  });

  test('Andere Wettbewerbe haben keine Zonen', () {
    expect(zonen('frauen_bundesliga', 12), everyElement(isNull));
    expect(zonen('dfb_pokal', 18), everyElement(isNull));
    expect(tabellenZone(null, 1, 18), isNull);
  });

  testWidgets('Vorschau: Bundesliga-Tabelle mit Zonen', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final rows = [
      for (var r = 1; r <= 18; r++)
        StandingRow(
          rank: r,
          team: TeamRef(id: 't$r', name: 'Verein $r', shortName: 'V$r'),
          played: 7,
          won: 0,
          draw: 0,
          lost: 0,
          goalsFor: 20 - r,
          goalsAgainst: r,
          points: 40 - 2 * r,
        ),
    ];
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: ListView(
          children: [
            for (final row in rows)
              TabellenZeile(
                row: row,
                eigene: row.rank == 9,
                zone: tabellenZone('bundesliga', row.rank, rows.length),
              ),
            const ZonenLegende(leagueId: 'bundesliga', teams: 18),
          ],
        ),
      ),
    ));
    expect(find.text('Champions League'), findsOneWidget);
    expect(find.text('Abstieg'), findsOneWidget);
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/tabellen_zonen.png'));
  });
}
