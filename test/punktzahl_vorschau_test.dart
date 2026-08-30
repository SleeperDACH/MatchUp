import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/punktzahl.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';

import 'support/schrift.dart';

/// Vorschau: **Punktstände vorher und nachher**, in den Größen, in denen sie
/// wirklich vorkommen. Ohne das Bild ist nicht zu beurteilen, ob der leisere
/// Bruchteil noch lesbar ist oder schon verschluckt wirkt.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Punktstände', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 620 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Widget paar(String titel, double a, double b, double groesse) {
      final stil = TextStyle(
        fontSize: groesse,
        height: 1,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titel,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 170,
                  child: Text('${formatPoints(a)} : ${formatPoints(b)}',
                      style: stil),
                ),
                const SizedBox(width: 8),
                const Text('→',
                    style: TextStyle(color: Colors.white24, fontSize: 16)),
                const SizedBox(width: 12),
                Punktzahl(a, stil: stil.copyWith(color: const Color(0xFF4ADE6A))),
                Text(' : ', style: stil.copyWith(color: Colors.white54)),
                Punktzahl(b, stil: stil.copyWith(color: const Color(0xFFF23030))),
              ],
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            paar('MATCHUP-KARTE (32)', 128.4, 99.5, 32),
            paar('LIVE, KNAPP (32)', 48.4, 51.2, 32),
            paar('GLATTE ZAHLEN (32)', 92, 78, 32),
            paar('DETAILKOPF (28)', 221.1, 187.4, 28),
            paar('DREISTELLIG (28)', 108.5, 99.9, 28),
            paar('KLEIN, IN DER LISTE (16)', 12.5, 7.5, 16),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(find.byType(ListView),
        matchesGoldenFile('goldens/punktzahl_vorschau.png'));
  });
}
