import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/chat_message.dart';
import 'package:matchup/core/ui/league_chat.dart';

import 'support/schrift.dart';

/// **Was ungelesen ist, muss man sehen können.**
///
/// Gemeldet: *„Mir werden ungelesene Nachrichten angezeigt. Wenn ich aber auf
/// die Nachrichten gehe, kann ich nicht erkennen, welche damit gemeint sind."*
///
/// Zwei Ursachen lagen darunter:
///
/// * Die Gesprächsliste **kennzeichnete gar nichts** — gelesen und ungelesen
///   sahen gleich aus, während der rote Zähler „8" behauptete.
/// * Der Verlauf setzte die Lesemarke beim Aufbau auf *jetzt*. Die
///   ungelesenen Nachrichten waren also verschwunden, bevor man sie sehen
///   konnte. Der Schirm hält den Stand von **vor** dem Öffnen fest und zieht
///   davor die Linie „Neue Nachrichten".

ChatMessage _m(String id, String von, String text, DateTime wann) =>
    ChatMessage(id: id, userId: von, body: text, createdAt: wann);

Widget _chat({DateTime? neuAb, required List<ChatMessage> msgs}) =>
    ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: LeagueChat(
            messages: AsyncValue.data(msgs),
            names: const {'ich': 'SFV03', 'du': 'Lewin9'},
            avatars: const {},
            myId: 'ich',
            neuAb: neuAb,
            onSend: (_, _) async {},
            onRetry: () {},
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  final gestern = DateTime(2026, 9, 5, 12);
  final spaeter = DateTime(2026, 9, 5, 18);

  testWidgets('die Linie steht vor der ersten neuen fremden Nachricht',
      (tester) async {
    await tester.pumpWidget(_chat(
      neuAb: DateTime(2026, 9, 5, 15),
      msgs: [
        _m('1', 'du', 'Alt und gelesen', gestern),
        _m('2', 'ich', 'Meine Antwort', gestern.add(const Duration(hours: 1))),
        _m('3', 'du', 'Neu und ungelesen', spaeter),
        _m('4', 'du', 'Auch neu', spaeter.add(const Duration(minutes: 5))),
      ],
    ));
    await tester.pump();

    expect(find.text('Neue Nachrichten'), findsOneWidget,
        reason: 'genau einmal — eine Linie über jeder neuen Nachricht wäre '
            'keine Grenze mehr, sondern ein Muster');
  });

  testWidgets('ohne Lesestand steht keine Linie', (tester) async {
    await tester.pumpWidget(_chat(neuAb: null, msgs: [
      _m('1', 'du', 'Hallo', gestern),
      _m('2', 'du', 'Noch was', spaeter),
    ]));
    await tester.pump();
    expect(find.text('Neue Nachrichten'), findsNothing,
        reason: 'wer nie gelesen hat, bekommt keine Grenze mitten im Verlauf');
  });

  testWidgets('eigene Nachrichten lösen die Linie nicht aus', (tester) async {
    // **Was man selbst geschrieben hat, hat man gelesen.** Ohne diese Regel
    // stünde die Linie über der eigenen letzten Antwort — und damit an der
    // Stelle, an der garantiert nichts Neues ist.
    await tester.pumpWidget(_chat(
      neuAb: DateTime(2026, 9, 5, 15),
      msgs: [
        _m('1', 'du', 'Alt', gestern),
        _m('2', 'ich', 'Meine neue Antwort', spaeter),
      ],
    ));
    await tester.pump();
    expect(find.text('Neue Nachrichten'), findsNothing);
  });

  testWidgets('alles gelesen: keine Linie', (tester) async {
    await tester.pumpWidget(_chat(
      neuAb: DateTime(2026, 9, 6),
      msgs: [
        _m('1', 'du', 'Alt', gestern),
        _m('2', 'du', 'Auch alt', spaeter),
      ],
    ));
    await tester.pump();
    expect(find.text('Neue Nachrichten'), findsNothing);
  });
}
