import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/chat_message.dart';
import 'package:matchup/core/ui/league_chat.dart';

/// **Eine gesendete Nachricht steht sofort da.**
///
/// Gemeldet: „Wenn man eine Nachricht an eine Person oder in die Ligagruppe
/// schickt, wird die nicht direkt nach dem Absenden angezeigt, sondern ein paar
/// Sekunden verzögert." Der Verlauf zeigte nur, was über Realtime zurückkam.
///
/// Geprüft wird, was davon abhängt: Die Blase steht da, **während** der Server
/// noch nicht geantwortet hat; sie wird nicht verdoppelt, wenn die echte Zeile
/// ankommt; und ein Fehlschlag nimmt sie wieder weg und gibt den Text zurück.

class _Rahmen extends StatefulWidget {
  const _Rahmen({required this.onSend, required this.verlauf});

  final Future<void> Function(String, String?) onSend;
  final ValueNotifier<List<ChatMessage>> verlauf;

  @override
  State<_Rahmen> createState() => _RahmenState();
}

class _RahmenState extends State<_Rahmen> {
  @override
  Widget build(BuildContext context) => ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: widget.verlauf,
              builder: (_, liste, _) => LeagueChat(
                messages: AsyncValue.data(liste),
                names: const {'u1': 'SFV03'},
                myId: 'u1',
                onSend: widget.onSend,
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
}

Future<void> _tippenUndSenden(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('Senden'));
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('die Blase steht da, bevor der Server antwortet', (tester) async {
    final antwort = Completer<void>();
    final verlauf = ValueNotifier<List<ChatMessage>>(const []);
    await tester.pumpWidget(
      _Rahmen(onSend: (_, _) => antwort.future, verlauf: verlauf),
    );

    await _tippenUndSenden(tester, 'Bin dabei');
    expect(find.text('Bin dabei'), findsOneWidget);
    // Das Eingabefeld ist sofort wieder frei.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);

    // Server bestätigt, und die echte Zeile kommt an: genau **eine** Blase.
    antwort.complete();
    verlauf.value = [
      ChatMessage(
        id: 'echt1',
        userId: 'u1',
        body: 'Bin dabei',
        createdAt: DateTime.now(),
      ),
    ];
    await tester.pump();
    expect(find.text('Bin dabei'), findsOneWidget);
  });

  testWidgets('zweimal derselbe Text sind zwei Nachrichten', (tester) async {
    final verlauf = ValueNotifier<List<ChatMessage>>(const []);
    await tester.pumpWidget(
      _Rahmen(onSend: (_, _) async {}, verlauf: verlauf),
    );
    await _tippenUndSenden(tester, 'ok');
    await _tippenUndSenden(tester, 'ok');
    expect(find.text('ok'), findsNWidgets(2));

    // Erst eine der beiden ist beim Server angekommen.
    verlauf.value = [
      ChatMessage(
          id: 'e1', userId: 'u1', body: 'ok', createdAt: DateTime.now()),
    ];
    await tester.pump();
    expect(find.text('ok'), findsNWidgets(2));
  });

  testWidgets('ein Fehlschlag nimmt die Blase weg und gibt den Text zurück',
      (tester) async {
    final verlauf = ValueNotifier<List<ChatMessage>>(const []);
    await tester.pumpWidget(
      _Rahmen(
        onSend: (_, _) async => throw Exception('offline'),
        verlauf: verlauf,
      ),
    );
    await _tippenUndSenden(tester, 'Hallo Liga');
    await tester.pump();

    final feld = tester.widget<TextField>(find.byType(TextField));
    expect(feld.controller!.text, 'Hallo Liga');
    // Der Text steht nur noch im Eingabefeld, nicht als Blase.
    expect(find.text('Hallo Liga'), findsOneWidget);
    expect(find.textContaining('konnte nicht gesendet werden'), findsOneWidget);
  });
}
