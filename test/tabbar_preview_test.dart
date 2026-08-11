import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/segmented_tab_bar.dart';

// Vorschau der Tab-Leiste (kein Regressionstest):
//   flutter test --update-goldens test/tabbar_preview_test.dart
// -> test/goldens/tabbar_preview.png
//
// Oben die vier Reiter der Spieldetails (scrollbar), darunter der Fall mit
// drei Reitern (gleichmäßig verteilt) — beide Varianten in einem Bild.

void main() {
  testWidgets('Vorschau: Segment-Tableiste', (tester) async {
    Widget leiste(List<String> titel) => DefaultTabController(
          length: titel.length,
          child: SegmentedTabBar(tabs: [for (final t in titel) Tab(text: t)]),
        );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          backgroundColor: MatchUpColors.base,
          body: Center(
            child: SizedBox(
              width: 402,
              child: RepaintBoundary(
                key: const Key('preview'),
                // Die Leiste ist selbst durchsichtig (AppBar ist im Theme
                // transparent) — für die Vorschau der echte App-Grund darunter.
                child: Container(
                  color: MatchUpColors.base,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    leiste(
                        ['Übersicht', 'Aufstellung', 'Statistik', 'Tabelle']),
                    const SizedBox(height: 10),
                    leiste(['Übersicht', 'Aufstellung', 'Statistik']),
                    const SizedBox(height: 10),
                    // Fantasy-Liga und Draft-Raum: Symbol über dem Text.
                    DefaultTabController(
                      length: 4,
                      child: SegmentedTabBar(tabs: const [
                        Tab(
                            icon: Icon(Icons.dashboard_outlined, size: 20),
                            text: 'Übersicht'),
                        Tab(
                            icon: Icon(Icons.swap_horiz, size: 20),
                            text: 'MatchUp'),
                        Tab(
                            icon: Icon(Icons.shield_outlined, size: 20),
                            text: 'Kader'),
                        Tab(
                            icon: Icon(Icons.leaderboard_outlined, size: 20),
                            text: 'Tabelle'),
                      ]),
                    ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/tabbar_preview.png'));
  });
}
