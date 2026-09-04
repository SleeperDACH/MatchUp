import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/typografie.dart';
import 'package:matchup/app/widgets/navi_kapsel.dart';

import 'support/schrift.dart';

// Vorschau der unteren Navi-Kapsel (kein Regressionstest):
//   flutter test --update-goldens test/navileiste_vorschau_test.dart
// -> test/goldens/navileiste.png
//
// **Sie steht über zwei Untergründen, und das ist der ganze Zweck.** Die
// Kapsel schwebt über dem, was der Tab gerade zeigt (`extendBody`), und der
// Newsblock des Startbildschirms bringt große helle Bilder mit. Ein Bild nur
// über schwarzem Grund würde genau den Fall auslassen, an dem die vorige
// Fassung scheiterte: weiß getöntes Glas wurde dort zu grauem Matsch, und die
// gedämpften Ziele verloren ihren Kontrast.
//
// Jede Zeile zeigt außerdem einen anderen aktiven Reiter — die Marke muss an
// jeder der drei Stellen sitzen, auch am längsten Wort („Favoriten").

/// Steht für den Inhalt, der unter der Kapsel durchläuft.
class _Untergrund extends StatelessWidget {
  const _Untergrund({required this.hell});
  final bool hell;

  @override
  Widget build(BuildContext context) {
    if (!hell) return const ColoredBox(color: MatchUpColors.base);
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1466C8),
            Color(0xFF3FA0F5),
            Color(0xFFE8EEF6),
            Color(0xFF0B2E5C),
          ],
          stops: [0.0, 0.35, 0.62, 1.0],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: untere Navi-Kapsel', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 620 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: MatchUpColors.base,
          body: Column(
            children: [
              for (var i = 0; i < 3; i++)
                for (final hell in [false, true])
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Untergrund(hell: hell),
                        Align(
                          alignment: Alignment.center,
                          child: NaviKapsel(index: i, onSelected: (_) {}),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/navileiste.png'));
  });

  testWidgets('Jedes Ziel trägt Namen und Auswahlzustand für die Vorlesehilfe',
      (tester) async {
    // Ohne das heißen die drei Ziele für VoiceOver „Schaltfläche" — dieselbe
    // Lücke, die schon 24 Symbolknöpfe der App hatten. Material's
    // `NavigationBar` brachte das mit; die selbst gebaute Kapsel nicht.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: NaviKapsel(index: 1, onSelected: (_) {}),
        ),
      ),
    );

    for (final wort in ['Home', 'Live', 'Favoriten']) {
      expect(
        find.bySemanticsLabel(wort),
        findsOneWidget,
        reason: '$wort muss als benannte Schaltfläche ansagbar sein',
      );
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('Live')),
      matchesSemantics(
        label: 'Live',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('Die Tastflächen halten das iOS-Mindestmaß von 44 Punkten',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: NaviKapsel(index: 0, onSelected: (_) {}),
          ),
        ),
      ),
    );
    for (final wort in ['Home', 'Live', 'Favoriten']) {
      final feld = tester.getSize(
          find.ancestor(of: find.text(wort), matching: find.byType(InkWell)));
      expect(feld.width, greaterThanOrEqualTo(44),
          reason: 'Tastfläche $wort zu schmal');
      expect(feld.height, greaterThanOrEqualTo(44),
          reason: 'Tastfläche $wort zu flach');
    }
  });

  test('Die reservierte Höhe passt zur Kapsel', () {
    // `extendBody: true` legt die Kapsel über den Body; der Live-Tab hält den
    // Platz selbst frei und liest dafür dieselbe Zahl. Sie muss die
    // tatsächliche Höhe treffen, sonst klebt der Inhalt darunter.
    expect(navBarHeight, 58);
    expect(Schrift.winzig, 10);
  });
}
