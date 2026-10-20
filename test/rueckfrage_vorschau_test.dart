import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/ui/rueckfrage.dart';

import 'support/schrift.dart';

/// Vorschau der **Rückfrage als Blatt** (19.10.2026, auf Ansage: „wieder
/// dieses komische Box-Design"). Zwei Fälle: Bestätigen mit eigenem Inhalt
/// (Draft-Pick) und eine rote Rückfrage (Droppen).
///   flutter test --update-goldens test/rueckfrage_vorschau_test.dart
void main() {
  setUpAll(ladeSchrift);

  Future<void> zeige(WidgetTester tester, Widget blatt, String datei) async {
    tester.view.physicalSize = const Size(402 * 3, 520 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: blatt)),
    ));
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(Scaffold), matchesGoldenFile(datei));
  }

  testWidgets('Vorschau: Draft-Pick', (tester) async {
    await zeige(
      tester,
      const RueckfrageBlatt(
        titel: 'Draften?',
        ja: 'Draften',
        inhalt: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 22, child: Text('BVB')),
          title: Text('Nico Schlotterbeck',
              style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Abwehr · Dortmund · Ø 8,4'),
        ),
      ),
      'goldens/rueckfrage_draft.png',
    );
    expect(find.text('DRAFTEN?'), findsOneWidget);
  });

  testWidgets('Vorschau: rote Rückfrage', (tester) async {
    await zeige(
      tester,
      const RueckfrageBlatt(
        titel: 'Nico Schlotterbeck droppen?',
        text: 'Der Spieler verlässt deinen Kader und kommt für 24 Stunden '
            'auf den Waiver-Wire.',
        ja: 'Droppen',
        gefahr: true,
      ),
      'goldens/rueckfrage_gefahr.png',
    );
  });
}
