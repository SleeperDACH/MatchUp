import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/competition_picker.dart';
import 'package:matchup/core/models/models.dart';

// Vorschau der Wettbewerbsauswahl (kein Regressionstest):
//   flutter test --update-goldens test/competition_picker_preview_test.dart
// -> test/goldens/competition_picker.png
//
// Die offiziellen Logos kommen aus dem Netz und fehlen im Test; dort greift
// das gezeichnete Emblem. Geprüft wird hier Form und Zustand der Pillen.
void main() {
  testWidgets('Vorschau: Wettbewerbe wählen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: MatchUpColors.base,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CompetitionPicker(
                leagues: Leagues.tippspiel,
                selected: const {'bundesliga', 'dfb_pokal'},
                onToggle: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(find.byType(CompetitionPicker),
        matchesGoldenFile('goldens/competition_picker.png'));
  });
}
