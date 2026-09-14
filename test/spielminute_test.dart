import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/match_detail_screen.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/match_detail.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/tippspiel/providers.dart';

import 'support/schrift.dart';

/// **Die laufende Spielminute im Kopf der Spieldetails.**
///
/// In dieser Datei stand lange, der Feed liefere keine Minute. Er liefert sie
/// in `periods`: Der Abschnitt mit `ticking: true` trägt sie als die Zahl, die
/// man anzeigt — einschließlich Nachspielzeit (1. Halbzeit `minutes: 47` bei
/// 45 plus 2).
///
/// Drei Zustände müssen sich unterscheiden, und der mittlere ist der Grund für
/// `phase`: [MatchDetail.status] faltet die Pause auf `live` zusammen, aber
/// dort läuft keine Uhr. Ohne den Rohwert stünde im Kopf „LIVE" ohne Zahl, und
/// niemand wüsste, ob die Uhr steht oder die Auskunft fehlt.
MatchDetail _spiel({int? minute, String? phase, FixtureStatus? status}) =>
    MatchDetail(
      id: 'sportmonks:1',
      home: const TeamRef(id: 'h', name: 'Union Berlin', shortName: 'FCU'),
      away: const TeamRef(id: 'a', name: 'Schalke 04', shortName: 'S04'),
      kickoff: DateTime(2026, 9, 11, 18, 30),
      status: status ?? FixtureStatus.live,
      homeScore: 1,
      awayScore: 3,
      goals: const [],
      minute: minute,
      phase: phase,
    );

Future<void> _zeige(WidgetTester tester, MatchDetail d) async {
  tester.view.physicalSize = const Size(402 * 3, 400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [matchDetailProvider.overrideWith((ref, id) async => d)],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const MatchDetailScreen(fixtureId: 'sportmonks:1'),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(ladeSchrift);

  testWidgets('die laufende Minute steht im Kopf', (tester) async {
    await _zeige(tester, _spiel(minute: 67, phase: 'INPLAY_2ND_HALF'));

    expect(find.text("67'"), findsOneWidget);
    // **„LIVE" sagt dasselbe wie der pulsierende Punkt daneben.** Die Minute
    // sagt etwas Neues und nimmt seinen Platz ein.
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('in der Pause steht „Halbzeit"', (tester) async {
    // Die Quelle liefert in der Pause keine Minute. Eine 45 stehen zu lassen
    // wäre eine Uhr, die lügt.
    await _zeige(tester, _spiel(minute: null, phase: 'HT'));

    expect(find.text('Halbzeit'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('ohne Uhr und ohne Pause bleibt es beim Wort', (tester) async {
    // Unterbrechung, Verlängerung ohne Uhr, unvollständige Antwort: Dann ist
    // „läuft" alles, was sich belegen lässt.
    await _zeige(tester, _spiel(minute: null, phase: 'INPLAY_ET'));

    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('ein beendetes Spiel zeigt keine Minute', (tester) async {
    await _zeige(
        tester,
        _spiel(minute: 103, phase: 'FT', status: FixtureStatus.finished));

    expect(find.text("103'"), findsNothing);
    expect(find.text('beendet'), findsOneWidget);
  });

  group('MatchDetail.istPause', () {
    test('kennt die Schreibweisen der Quelle', () {
      expect(_spiel(phase: 'HT').istPause, isTrue);
      expect(_spiel(phase: 'BREAK').istPause, isTrue);
      expect(_spiel(phase: 'INPLAY_1ST_HALF').istPause, isFalse);
      expect(_spiel(phase: null).istPause, isFalse);
    });
  });
}
