import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/match_detail_screen.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/match_detail.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/tippspiel/providers.dart';

import 'support/schrift.dart';

/// Vorschau des **Spielverlaufs** — wegen des Eigentors.
///
/// Zwei Fehler steckten hier hintereinander. Erst fehlte jedes Eigentor ganz
/// (der Typ heißt in der Quelle „Own Goal" mit Leerzeichen, der Abgleich
/// suchte „owngoal"). Und danach sah es aus wie ein normaler Treffer: grüner
/// Ball, und darunter der `related`-Spieler als wäre er der Vorlagengeber.
///
/// Ein Eigentor ist aber kein Treffer für die eigene Mannschaft. Es trägt
/// deshalb einen **roten** Ball, das Wort „Eigentor", und **keinen**
/// Vorlagengeber.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Spielverlauf mit Eigentor', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 520 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const heim = TeamRef(id: 'bvb', name: 'Borussia Dortmund', shortName: 'BVB');
    const gast = TeamRef(id: 'hsv', name: 'Hamburger SV', shortName: 'HSV');

    final detail = MatchDetail(
      id: 'sportmonks:19735196',
      home: heim,
      away: gast,
      kickoff: DateTime(2026, 8, 29, 18, 30),
      status: FixtureStatus.finished,
      homeScore: 2,
      awayScore: 0,
      goals: const [],
      events: const [
        MatchEvent(
            minute: 9,
            type: 'Goal',
            forHomeTeam: true,
            player: 'Serhou Guirassy',
            related: 'Konstantinos Karetsas',
            result: '1:0'),
        MatchEvent(
            minute: 45,
            extra: 1,
            // **Genau die Schreibweise der Quelle**, mit Leerzeichen.
            type: 'Own Goal',
            forHomeTeam: false,
            player: 'Sebastiaan Bornauw',
            // Die Quelle liefert hier trotzdem einen Spieler — er darf nicht
            // als Vorlagengeber erscheinen.
            related: 'Giannis Konstantelias',
            result: '2:0'),
        MatchEvent(
            minute: 77,
            type: 'Redcard',
            forHomeTeam: true,
            player: 'Samuele Inácio'),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        matchDetailProvider.overrideWith((ref, id) async => detail),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const MatchDetailScreen(fixtureId: 'sportmonks:19735196'),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Das Eigentor steht im Verlauf …
    expect(find.text('Sebastiaan Bornauw'), findsWidgets);
    // … ist als solches benannt …
    expect(find.text('Eigentor'), findsOneWidget);
    // … und nennt keinen Vorlagengeber.
    expect(find.text('Giannis Konstantelias'), findsNothing,
        reason: 'Beim Eigentor gibt es keine Vorlage');
    // Der reguläre Treffer nennt seine weiter.
    expect(find.text('Konstantinos Karetsas'), findsOneWidget);

    await expectLater(find.byType(MatchDetailScreen),
        matchesGoldenFile('goldens/spielverlauf_eigentor.png'));
  });
}
