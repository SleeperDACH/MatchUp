import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/kapitelmarke.dart';
import 'package:matchup/app/widgets/karte.dart';

import 'support/schrift.dart';

/// Vorschau der **Bausteine des Tippspiel-Bereichs** nach dem Umbau auf die
/// Fantasy-Regeln: Kartengrund mit Haarlinie, Hauch statt farbiger Ränder,
/// Kapitelmarke als Rubrik.
///
/// Die Schirme selbst haben keine Vorschau — sie hängen an einem halben Dutzend
/// Providern. Die **Bausteine** lassen sich aber einzeln zeigen, und genau an
/// ihnen hing der Umbau: Vorher trugen drei von ihnen eine gefüllte Farbfläche
/// *und* einen farbigen Rahmen, also zwei Signale für dieselbe Auskunft.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Tippspiel-Bausteine', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const gruen = Color(0xFF4ADE6A);
    const gold = Color(0xFFFFC83D);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            const Kapitelmarke('Samstag, 13. September', farbe: gruen),
            Karte(
              padding: EdgeInsets.zero,
              onTap: () {},
              child: const ListTile(
                leading: Icon(Icons.gavel_outlined, size: 20, color: gruen),
                title: Text('Regeln & Punkteverteilung'),
                subtitle: Text('Wie viele Punkte welcher Tipp bringt'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 8),
            Karte(
              hauch: gruen,
              padding: EdgeInsets.zero,
              onTap: () {},
              child: const ListTile(
                leading: Icon(Icons.emoji_events_outlined, color: gruen),
                title: Text('Bonustipps',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle:
                    Text('Saison-Prognosen abgeben — vor dem ersten Spieltag.'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 8),
            Karte(
              padding: EdgeInsets.zero,
              onTap: () {},
              child: const ListTile(
                leading: Icon(Icons.leaderboard_outlined),
                title: Text('Bonustipp-Tabelle',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Die Saison-Prognosen aller Mitglieder.'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 8),
            Karte(
              padding: EdgeInsets.zero,
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.key, size: 18),
                title: Text('ABC123',
                    style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
                subtitle: Text('Einladungscode — antippen zum Kopieren'),
                trailing: Icon(Icons.copy, size: 16),
              ),
            ),
            const Kapitelmarke('Bonustipps', farbe: gold),
            Karte(
              hauch: gold,
              padding: const EdgeInsets.all(12),
              child: const Row(children: [
                Icon(Icons.timelapse, size: 18, color: gold),
                SizedBox(width: 8),
                Expanded(
                    child: Text('Abgabe bis zum ersten Anstoß: '
                        '5. September 20:30 Uhr.')),
              ]),
            ),
            const SizedBox(height: 8),
            Karte(
              hauch: gruen,
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: true,
                onChanged: (_) {},
                title: const Text('Bonustipps aktiv'),
                subtitle: const Text('Saison-Prognosen vor dem ersten Spieltag'),
              ),
            ),
            const SizedBox(height: 8),
            Karte(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: false,
                onChanged: (_) {},
                title: const Text('Duelle aktiv'),
                subtitle: const Text('Jeder gegen jeden, Spieltag für Spieltag'),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(find.byType(ListView),
        matchesGoldenFile('goldens/tippspiel_bausteine.png'));
  });
}
