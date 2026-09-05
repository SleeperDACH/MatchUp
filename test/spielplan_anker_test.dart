import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/team_fixture_list.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';

import 'support/schrift.dart';

/// **Der Spielplan öffnet beim nächsten Spiel.**
///
/// Gewünscht: *„Die nächsten Spiele sollen ganz oben angezeigt werden. Dann
/// kann man aber trotzdem noch nach oben wischen, und dort steht dann
/// ‚Vorherige Spiele anzeigen'. Die gehen dann von oben nach unten, sodass die
/// zuletzt passierten ganz unten sind."*
///
/// Drei Zusicherungen, und jede war einmal eine Fassung, die fiel:
///
/// * Beim Öffnen steht **Nächste Spiele** oben — nicht ein Ergebnis, nicht
///   eine Überschrift darüber.
/// * Die Vergangenheit liegt **darüber** und liest sich von oben nach unten,
///   das jüngste Ergebnis unmittelbar über der Trennstelle.
/// * Das Aufklappen **verschiebt nichts**. Die Zeilen entstehen oberhalb des
///   Ankers; unter dem Daumen bleibt alles stehen.

TeamFixture _f(
  String heim,
  DateTime anstoss,
  FixtureStatus status, {
  int? tore,
}) => TeamFixture(
  id: 'sportmonks:$heim',
  kickoff: anstoss,
  status: status,
  leagueName: 'Bundesliga',
  round: 1,
  home: TeamRef(id: heim, name: heim, shortName: heim),
  away: const TeamRef(id: 'gast', name: 'FC Gast', shortName: 'GAS'),
  homeScore: tore,
  awayScore: tore == null ? null : 0,
);

/// Drei Ergebnisse und zwei kommende Partien — die Mischung, die ein Verein
/// mitten in der Saison hat.
final _spielplan = <TeamFixture>[
  _f('Aeltestes', DateTime(2026, 8, 15, 15, 30), FixtureStatus.finished,
      tore: 1),
  _f('Mittleres', DateTime(2026, 8, 22, 15, 30), FixtureStatus.finished,
      tore: 2),
  _f('Juengstes', DateTime(2026, 8, 29, 15, 30), FixtureStatus.finished,
      tore: 3),
  _f('Naechstes', DateTime(2026, 9, 12, 20, 30), FixtureStatus.scheduled),
  _f('Uebernaechstes', DateTime(2026, 9, 19, 15, 30), FixtureStatus.scheduled),
];

Widget _schirm(List<TeamFixture> fixtures) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: SpielplanAnsicht(fixtures: fixtures)),
);

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('beim Öffnen steht das nächste Spiel oben', (tester) async {
    await tester.pumpWidget(_schirm(_spielplan));
    await tester.pump();

    final kopf = tester.getTopLeft(find.text('NÄCHSTE SPIELE')).dy;
    expect(kopf, lessThan(40),
        reason: 'die Trennstelle ist der Anfang des Schirms');
    expect(kopf, greaterThanOrEqualTo(0));

    expect(tester.getTopLeft(find.text('Naechstes')).dy, greaterThan(kopf));
    expect(
      find.text('Juengstes'),
      findsNothing,
      reason: 'das Ergebnis liegt über der Trennstelle, also außer Sicht',
    );
  });

  testWidgets('nach oben steht „Vorherige Spiele anzeigen"', (tester) async {
    await tester.pumpWidget(_schirm(_spielplan));
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(find.text('Vorherige Spiele anzeigen'), findsOneWidget);
    expect(find.text('3'), findsOneWidget,
        reason: '„anzeigen" allein verrät nicht, ob drei Zeilen kommen '
            'oder eine halbe Saison');
  });

  testWidgets('aufgeklappt: das jüngste Ergebnis sitzt unten', (tester) async {
    await tester.pumpWidget(_schirm(_spielplan));
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorherige Spiele anzeigen'));
    await tester.pumpAndSettle();

    // Ganz nach oben, damit alle drei Ergebnisse im Bild stehen.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
    await tester.pumpAndSettle();

    final marke = tester.getTopLeft(find.text('VORHERIGE SPIELE')).dy;
    final alt = tester.getTopLeft(find.text('Aeltestes')).dy;
    final mitte = tester.getTopLeft(find.text('Mittleres')).dy;
    final jung = tester.getTopLeft(find.text('Juengstes')).dy;

    expect(marke, lessThan(alt), reason: 'die Marke steht über den Spielen');
    expect(alt, lessThan(mitte));
    expect(mitte, lessThan(jung),
        reason: 'von oben nach unten — das zuletzt Passierte ganz unten');
  });

  testWidgets('das Aufklappen verschiebt nichts', (tester) async {
    await tester.pumpWidget(_schirm(_spielplan));
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
    await tester.pumpAndSettle();
    final vorher = tester.getTopLeft(find.text('NÄCHSTE SPIELE')).dy;

    await tester.tap(find.text('Vorherige Spiele anzeigen'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('NÄCHSTE SPIELE')).dy,
      closeTo(vorher, 0.5),
      reason: 'die Zeilen entstehen oberhalb des Ankers — unter dem Daumen '
          'darf nichts springen',
    );
  });

  testWidgets('ohne kommende Spiele steht die Vergangenheit offen da',
      (tester) async {
    // Sonst wäre ein Knopf die Hürde vor dem einzigen, was da ist.
    final nurErgebnisse = _spielplan
        .where((f) => f.status == FixtureStatus.finished)
        .toList();
    await tester.pumpWidget(_schirm(nurErgebnisse));
    await tester.pump();

    expect(find.text('Vorherige Spiele anzeigen'), findsNothing);
    expect(find.text('NÄCHSTE SPIELE'), findsNothing);
  });
}
