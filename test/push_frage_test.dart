import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/push/push_frage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/schrift.dart';

void main() {
  setUpAll(ladeSchrift);

  test('ohne „Später" ist die Frage fällig', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await pushFrageFaellig(), isTrue);
  });

  test('„Später" hält zwei Wochen, danach wird wieder gefragt', () async {
    SharedPreferences.setMockInitialValues({});
    final heute = DateTime(2026, 10, 29, 12);
    await pushFrageVertagen(jetzt: heute);
    expect(await pushFrageFaellig(jetzt: heute.add(const Duration(days: 13))),
        isFalse);
    expect(await pushFrageFaellig(jetzt: heute.add(const Duration(days: 14))),
        isTrue);
  });

  testWidgets('Vorschau: das Blatt nennt den Verein, Erlauben gibt true',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    bool? antwort;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async =>
                  antwort = await zeigePushFrage(context, verein: 'Hannover'),
              child: const Text('fragen'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('fragen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bei Hannover spannend'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/push_frage.png'));
    await tester.tap(find.text('Benachrichtigungen erlauben'));
    await tester.pumpAndSettle();
    expect(antwort, isTrue);
  });
}
