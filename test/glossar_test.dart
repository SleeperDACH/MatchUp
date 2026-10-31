import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/glossar.dart';
import 'package:matchup/app/glossar_screen.dart';
import 'package:matchup/app/theme.dart';

import 'support/schrift.dart';

/// Das Glossar im Profil (Punkt 7 der Nutzer-Analyse).
void main() {
  setUpAll(ladeSchrift);

  test('jeder Begriff steht einmal da, kurz', () {
    final titel = [for (final g in glossar) g.e.titel];
    expect(titel.toSet().length, titel.length);
    for (final g in glossar) {
      // Höchstens vier Sätze — „keine langen Texte".
      final saetze = RegExp(r'[.!?](\s|$)').allMatches(g.e.text).length;
      expect(saetze, lessThanOrEqualTo(4), reason: g.e.titel);
    }
  });

  test('Suche trifft Begriff und Text, ohne Groß/Klein', () {
    expect(glossarSuche('waiver').map((g) => g.e.titel),
        containsAll(['Waiver', 'Waiver-Priorität']));
    expect(glossarSuche('ÄLTESTE'), hasLength(1)); // nur „Form"
    expect(glossarSuche(''), hasLength(glossar.length));
  });

  test('je Bereich alphabetisch', () {
    for (final b in GlossarBereich.values) {
      final titel = [
        for (final g in glossarSuche(''))
          if (g.bereich == b) glossarSchluessel(g.e.titel),
      ];
      expect(titel, [...titel]..sort(), reason: b.titel);
    }
    final fantasy = [
      for (final g in glossarSuche(''))
        if (g.bereich == GlossarBereich.fantasy) g.e.titel,
    ];
    expect(fantasy.first, 'Aufstellung gesperrt');
  });

  testWidgets('Vorschau: Glossar mit Suche', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const GlossarScreen(),
    ));
    expect(find.text('Draft'), findsOneWidget);
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/glossar.png'));

    await tester.enterText(find.byType(TextField), 'snake');
    await tester.pump();
    expect(find.text('Snake-Draft'), findsOneWidget);
    expect(find.text('Trade'), findsNothing);

    await tester.enterText(find.byType(TextField), 'xyzq');
    await tester.pump();
    expect(find.textContaining('steht hier nichts'), findsOneWidget);
  });
}
