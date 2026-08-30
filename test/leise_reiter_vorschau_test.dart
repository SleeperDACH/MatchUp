import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/leise_reiter.dart';
import 'package:matchup/app/widgets/matchup_chevron.dart';

import 'support/schrift.dart';

/// Vorschau der **Reiterleiste** in ihren beiden Einbauorten.
///
/// Sie steckt in der Fantasy-Liga als `AppBar.bottom` (vier Wörter) und im
/// Favoriten-Tab mitten im Schirm (zwei Wörter). Der Fehler, der sie in die
/// Überarbeitung gebracht hat, war nur im ersten Fall zu sehen: Der Strich saß
/// auf der Unterkante, und die erste Karte begann direkt darunter — er sah aus,
/// als gehöre er zur Karte. Deshalb steht hier unter jeder Leiste eine
/// angedeutete Karte: Ohne sie wäre der Abstand nicht zu beurteilen.
void main() {
  setUpAll(ladeSchrift);

  Widget karte(String text) => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D27),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2E3A)),
        ),
        alignment: Alignment.center,
        child: Text(text,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      );

  // Liga-Leiste: Symbol **und** Wort bei allen vieren. An zweiter Stelle das
  // Markenzeichen — aktiv in den Markenfarben, ruhend mitgedämpft.
  final symbole = {
    0: (bool aktiv, Color farbe) =>
        Icon(Icons.grid_view_outlined, size: 17, color: farbe),
    1: (bool aktiv, Color farbe) =>
        MatchUpChevron(size: 17, color: aktiv ? null : farbe),
    2: (bool aktiv, Color farbe) =>
        Icon(Icons.people_outline, size: 19, color: farbe),
    3: (bool aktiv, Color farbe) =>
        Icon(Icons.leaderboard_outlined, size: 17, color: farbe),
  };

  Widget fall(String titel, List<String> reiter, int aktiv,
          {bool mitLogo = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(titel,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            ),
            DefaultTabController(
              length: reiter.length,
              initialIndex: aktiv,
              child: LeiseReiter(
                titel: reiter,
                horizontal: 12,
                symbole: mitLogo ? symbole : const {},
              ),
            ),
            karte('Inhalt beginnt hier'),
          ],
        ),
      );

  testWidgets('Vorschau: Reiterleiste', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 860 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.only(top: 16),
            children: [
              fall('FANTASY-LIGA · ERSTER REITER', const [
                'Übersicht',
                'MatchUp',
                'Kader',
                'Tabelle',
              ], 0, mitLogo: true),
              fall('FANTASY-LIGA · DRITTER REITER', const [
                'Übersicht',
                'MatchUp',
                'Kader',
                'Tabelle',
              ], 2, mitLogo: true),
              fall('FANTASY-LIGA · MARKENREITER AKTIV', const [
                'Übersicht',
                'MatchUp',
                'Kader',
                'Tabelle',
              ], 1, mitLogo: true),
              fall('FAVORITEN-TAB', const ['Spielplan', 'News'], 0),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ListView),
      matchesGoldenFile('goldens/leise_reiter_vorschau.png'),
    );
  });
}
