import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/chat_message.dart';
import 'package:matchup/core/ui/league_chat.dart';

import 'support/schrift.dart';

/// **Wer einen Chat öffnet, steht bei der neuesten Nachricht.**
///
/// Gemeldet: „Wenn man in einen Chat reingeht, ist man immer irgendwo."
/// Die Liste stand normal herum und sprang im ersten Frame auf
/// `maxScrollExtent` — eine Zahl, die eine `ListView.builder` zu diesem
/// Zeitpunkt nur schätzt, solange die Zeilen verschieden hoch sind. Je länger
/// der Verlauf, desto weiter daneben.
ChatMessage _msg(int i) => ChatMessage(
      id: 'm$i',
      userId: i.isEven ? 'ich' : 'du',
      body: i.isEven
          ? 'Nachricht $i'
          : 'Nachricht $i mit deutlich mehr Text, damit die Blasen '
              'verschieden hoch sind und die Schätzung der Liste daneben '
              'liegen kann.',
      createdAt: DateTime.now().subtract(Duration(minutes: 120 - i)),
    );

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Beim Öffnen steht die neueste Nachricht im Bild',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final nachrichten = [for (var i = 1; i <= 60; i++) _msg(i)];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: LeagueChat(
              messages: AsyncValue.data(nachrichten),
              myId: 'ich',
              names: const {'ich': 'SFV03', 'du': 'Eric'},
              avatars: const {},
              onSend: (_, __) async {},
              onRetry: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Die letzte Nachricht ist gebaut und sichtbar …
    expect(find.text('Nachricht 60'), findsOneWidget);
    // … die erste liegt weit oben außerhalb und ist gar nicht gebaut.
    expect(find.text('Nachricht 2'), findsNothing);
  });
}
