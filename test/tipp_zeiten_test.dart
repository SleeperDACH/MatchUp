import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/push/push_einstellungen.dart';
import 'package:matchup/features/push/ui/push_einstellungen_screen.dart';
import 'package:matchup/features/push/ui/tipp_zeiten_screen.dart';

import 'support/schrift.dart';

/// Tipp-Erinnerung individuell (auf Ansage, 17.10.2026).
void main() {
  setUpAll(ladeSchrift);

  test('Standard ist 2 Stunden und 30 Minuten', () {
    const e = PushEinstellungen.allesAn();
    expect(e.tippZeiten, isNull);
    expect(e.tippZeitenWirksam, [120, 30]);
    expect(PushEinstellungen.zeitenText(e.tippZeitenWirksam),
        '2 Std. und 30 Min. vorher');
  });

  test('die Auswahl: 30 Min., 1 Std., dann 2 bis 24 Stunden im 2er-Takt', () {
    expect(PushEinstellungen.tippZeitenWahl,
        [30, 60, for (var h = 2; h <= 24; h += 2) h * 60]);
    expect(PushEinstellungen.tippZeitenWahl, isNot(contains(180)),
        reason: 'ungerade Stunden gibt es nicht mehr');
  });

  test('gespeichert wird sortiert, ohne Doppelte; andere Schalter bleiben', () {
    final e = const PushEinstellungen.allesAn()
        .kopieMit('liga_chat', false)
        .mitTippZeiten([60, 600, 60, 30]);
    expect(e.tippZeiten, [600, 60, 30]);
    expect(e.an('liga_chat'), isFalse);
    final zeile = e.toRow('u1');
    expect(zeile['tipp_zeiten'], [600, 60, 30]);
    // Ein Schalter umlegen verliert die Zeiten nicht.
    expect(e.kopieMit('tipps', true).tippZeiten, [600, 60, 30]);
    // Und aus der Datenbank zurück.
    expect(PushEinstellungen.fromRow(zeile).tippZeiten, [600, 60, 30]);
    expect(PushEinstellungen.fromRow({'tipp_zeiten': null}).tippZeiten,
        isNull);
  });

  testWidgets('„Individuell einstellen" steht nur bei eingeschalteter Erinnerung',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 2300 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Future<void> baue(PushEinstellungen stand) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          pushEinstellungenProvider.overrideWith((ref) async => stand),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          // Seit dem 18.10.2026 stehen die Schalter je Bereich auf einem
          // eigenen Schirm.
          home: const PushBereichScreen(bereich: PushBereich.tippspiel),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await baue(const PushEinstellungen.allesAn());
    expect(find.text('Individuell einstellen'), findsOneWidget);
    expect(find.text('2 Std. und 30 Min. vorher'), findsOneWidget);

    await baue(const PushEinstellungen.allesAn().kopieMit('tipps', false));
    expect(find.text('Individuell einstellen'), findsNothing);
  });

  testWidgets('Vorschau: Zeitpunkte wählen, mindestens einer bleibt',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const TippZeitenScreen(stand: PushEinstellungen.allesAn()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Du wirst erinnert: 2 Std. und 30 Min. vorher.'),
        findsOneWidget);
    expect(find.text('3 Std.'), findsNothing);
    // 24 Stunden dazu, 30 Minuten weg.
    await tester.tap(find.text('24 Std.'));
    await tester.tap(find.text('30 Min.'));
    await tester.pump();
    expect(find.text('Du wirst erinnert: 24 Std. und 2 Std. vorher.'),
        findsOneWidget);
    expect(find.textContaining('Auf Standard zurücksetzen'), findsOneWidget);

    // Bis auf einen abwählen — der letzte bleibt.
    await tester.tap(find.text('24 Std.'));
    await tester.tap(find.text('2 Std.'));
    await tester.pump();
    expect(find.text('Du wirst erinnert: 2 Std. vorher.'), findsOneWidget);

    await expectLater(find.byType(TippZeitenScreen),
        matchesGoldenFile('goldens/tipp_zeiten.png'));
  });
}
