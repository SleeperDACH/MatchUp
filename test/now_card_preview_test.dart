import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/home_now.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/now_card.dart';

// Vorschau der Jetzt-Karte in ihren drei Zuständen (kein Regressionstest):
//   flutter test --update-goldens test/now_card_preview_test.dart
// -> test/goldens/now_card_preview.png

/// Lädt die App-Schrift, damit die Vorschau lesbaren Text zeigt statt der
/// Kästchen des Test-Standardfonts.
Future<void> ladeAppSchrift() async {
  final loader = FontLoader('BarlowCondensed');
  for (final schnitt in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    // Bewusst synchron gelesen: echtes Datei-I/O läuft im Fake-Async-Zone
    // eines Widget-Tests nie fertig, der Test würde hängen.
    final bytes = File('assets/fonts/BarlowCondensed-$schnitt.ttf')
        .readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  testWidgets('Vorschau: Jetzt-Karte (Tipps offen, Draft, alles getippt)',
      (tester) async {
    await initializeDateFormatting('de_DE');
    await ladeAppSchrift();
    // Fester Zeitpunkt: sonst zeigt jede Vorschau eine andere Restzeit.
    final now = DateTime(2026, 8, 18, 12, 0);

    final items = [
      NowItem(
        kind: NowKind.tips,
        label: 'Bundesliga 26/27',
        detail: 'Spieltag 3',
        deadline: now.add(const Duration(hours: 2, minutes: 14)),
        openTips: 5,
      ),
      NowItem(
        kind: NowKind.draft,
        label: 'DynastyTest',
        detail: 'Runde 4 · Pick 27',
        deadline: now.add(const Duration(minutes: 1, seconds: 42)),
        myTurn: true,
      ),
      NowItem(
        kind: NowKind.kickoff,
        label: 'Büro-Tippspiel',
        detail: 'Spieltag 3',
        deadline: now.add(const Duration(days: 2, hours: 3)),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: MatchUpColors.base,
          body: Center(
            child: SizedBox(
              width: 390,
              child: RepaintBoundary(
                key: const Key('preview'),
                child: Container(
                  color: MatchUpColors.base,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in items) ...[
                        NowCard(item: item, onOpen: () {}, jetzt: now),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/now_card_preview.png'));
  });
}
