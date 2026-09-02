import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/chat_message.dart';
import 'package:matchup/core/ui/league_chat.dart';

import 'support/schrift.dart';

/// **Nachrichten lassen sich kopieren — auch dort, wo nicht geantwortet wird.**
///
/// Gemeldet: „Wir brauchen außerdem die Funktion, dass man im Chat Nachrichten
/// kopieren sowie einfügen kann. Das funktioniert irgendwie nicht."
///
/// Zwei Löcher steckten dahinter, und das zweite ist das interessantere:
///
/// 1. Es gab **überhaupt keinen** Kopierweg. Die Blase war ein schlichtes
///    `Text`, das Aktionsblatt kannte nur „Antworten".
/// 2. Der Long-Press hing komplett an `onReply`. In Direktnachrichten
///    (`enableReply: false`) war er damit tot — man hielt drauf, und nichts
///    geschah. Genau das beschreibt „funktioniert irgendwie nicht": ein Griff,
///    der nichts tut, ist von einem fehlenden Griff nicht zu unterscheiden.
///
/// Der Test greift deshalb **beide** Fälle ab. Ohne die Korrektur fällt der
/// Direktnachrichten-Fall schon am Long-Press durch, der Ligafall am
/// fehlenden Eintrag.

final _nachrichten = <ChatMessage>[
  ChatMessage(
    id: 'm1',
    userId: 'u2',
    body: 'Waiver läuft Montag 15 Uhr ab.',
    createdAt: DateTime.utc(2026, 9, 1, 12),
  ),
];

Widget _chat({required bool enableReply}) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: LeagueChat(
            messages: AsyncValue.data(_nachrichten),
            names: const {'u1': 'SFV03', 'u2': 'Eric'},
            myId: 'u1',
            enableReply: enableReply,
            onSend: (_, _) async {},
            onRetry: () {},
          ),
        ),
      ),
    );

void main() {
  setUpAll(ladeSchrift);

  /// Fängt ab, was die App in die Zwischenablage legt.
  List<String> zwischenablage(WidgetTester tester) {
    final abgelegt = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          abgelegt.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return abgelegt;
  }

  testWidgets('Long-Press kopiert die Nachricht (Liga, mit Antworten)',
      (tester) async {
    final abgelegt = zwischenablage(tester);
    await tester.pumpWidget(_chat(enableReply: true));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Waiver läuft Montag 15 Uhr ab.'));
    await tester.pumpAndSettle();

    // Kopieren steht oben, Antworten bleibt darunter erhalten.
    expect(find.text('Kopieren'), findsOneWidget);
    expect(find.text('Antworten'), findsOneWidget);

    await tester.tap(find.text('Kopieren'));
    await tester.pumpAndSettle();

    expect(abgelegt, ['Waiver läuft Montag 15 Uhr ab.']);
    expect(find.text('Nachricht kopiert'), findsOneWidget);
  });

  testWidgets('Auch ohne Antworten öffnet der Long-Press das Blatt (DM)',
      (tester) async {
    final abgelegt = zwischenablage(tester);
    await tester.pumpWidget(_chat(enableReply: false));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Waiver läuft Montag 15 Uhr ab.'));
    await tester.pumpAndSettle();

    expect(find.text('Kopieren'), findsOneWidget);
    // Antworten wird hier nicht angeboten — das ist der Unterschied, nicht
    // ein totes Menü.
    expect(find.text('Antworten'), findsNothing);

    await tester.tap(find.text('Kopieren'));
    await tester.pumpAndSettle();

    expect(abgelegt, ['Waiver läuft Montag 15 Uhr ab.']);
  });

  testWidgets('Die Eingabezeile lässt Einfügen zu', (tester) async {
    await tester.pumpWidget(_chat(enableReply: true));
    await tester.pumpAndSettle();

    // Einfügen kommt vom System-Menü des Feldes. Das erscheint nur, solange
    // Auswahl und Kontextmenü nicht abgeschaltet sind — beides ist hier
    // Vorgabe und soll es bleiben.
    final feld = tester.widget<TextField>(find.byType(TextField));
    expect(feld.enableInteractiveSelection, isNot(false));
    expect(feld.readOnly, isFalse);
    expect(feld.contextMenuBuilder, isNotNull);
  });
}
