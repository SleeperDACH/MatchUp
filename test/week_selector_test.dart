import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/tippspiel/logic/tip_weeks.dart';
import 'package:meine_app/features/tippspiel/providers.dart';
import 'package:meine_app/features/tippspiel/ui/round_selector.dart';

Fixture _fx(String id, DateTime kickoff) => Fixture(
      id: id,
      leagueId: 'bl1',
      season: 2025,
      round: 1,
      roundName: 'Spieltag 1',
      kickoff: kickoff,
      home: const TeamRef(id: 'h', name: 'Heim', shortName: 'HEI'),
      away: const TeamRef(id: 'a', name: 'Aus', shortName: 'AUS'),
      status: FixtureStatus.scheduled,
    );

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  final weeks = buildWeeks([
    _fx('w1', DateTime(2025, 9, 6, 15, 30)), // Woche 1
    _fx('w2a', DateTime(2025, 9, 12, 20, 30)), // Woche 2, Fr
    _fx('w2b', DateTime(2025, 9, 14, 17, 30)), // Woche 2, So
    _fx('w3', DateTime(2025, 9, 20, 15, 30)), // Woche 3
  ]);

  Widget harness(int index, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(body: WeekSelector(weeks: weeks, index: index)),
        ),
      );

  testWidgets('WeekSelector zeigt „Woche N · Datumsspanne"', (tester) async {
    await tester.pumpWidget(harness(2));
    expect(find.textContaining('Woche 2 · 12.–14.'), findsOneWidget);
  });

  testWidgets('Pfeile begrenzt: erste Woche kein Zurück, letzte kein Vor',
      (tester) async {
    await tester.pumpWidget(harness(1));
    final left = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left));
    final right = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(left.onPressed, isNull, reason: 'Woche 1: kein Zurück');
    expect(right.onPressed, isNotNull);
  });

  testWidgets('Vor-Pfeil setzt selectedWeekProvider auf die nächste Woche',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: WeekSelector(weeks: weeks, index: 2)),
      ),
    ));
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(container.read(selectedWeekProvider), 3);
  });
}
