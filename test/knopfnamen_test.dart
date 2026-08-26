import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/ui/matchday_stepper.dart';

/// Ein Symbolknopf ohne `tooltip` hat für VoiceOver und TalkBack **keinen
/// Namen** — Flutter leitet aus `Icons.chevron_right` keine Beschriftung ab,
/// vorgelesen heißt der Knopf dann „Schaltfläche". Das betraf einmal 24 der
/// 43 [IconButton] der App, darunter beide Pfeile jeder Spieltagsauswahl.
///
/// Die Prüfung liest den Quelltext, statt Screens zu rendern: Die meisten
/// dieser Knöpfe stecken in privaten Klassen tief in Formularen, die ohne
/// halben Screen samt Providern nicht aufzubauen sind. Ein Widget-Test je
/// Knopf wäre der teurere Weg zur schwächeren Aussage — hier fällt jeder neue
/// namenlose Knopf auf, egal wo er entsteht.
void main() {
  test('Jeder IconButton in lib/ hat einen tooltip', () {
    final ohneNamen = <String>[];

    for (final datei in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final quelle = datei.readAsStringSync();
      // `IconButton(`, `IconButton.filled(`, `IconButton.outlined(` …
      for (final treffer
          in RegExp(r'IconButton(?:\.\w+)?\(').allMatches(quelle)) {
        final aufruf = quelle.substring(
            treffer.start, _endeDesAufrufs(quelle, treffer.end - 1) + 1);
        if (!aufruf.contains('tooltip:')) {
          final zeile = '\n'.allMatches(quelle.substring(0, treffer.start)).length + 1;
          ohneNamen.add('${datei.path}:$zeile');
        }
      }
    }

    expect(ohneNamen, isEmpty,
        reason: 'Diese Knöpfe heißen vorgelesen „Schaltfläche":\n'
            '${ohneNamen.join('\n')}');
  });

  testWidgets('Spieltagspfeile nennen ihr Ziel, nicht ihre Richtung',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MatchdayStepper(round: 7, onChanged: (_) {}, max: 34),
      ),
    ));

    // „Zurück" allein sagt nicht, wohin — die Zahl dazwischen gehört zu
    // keinem der beiden Knöpfe.
    expect(_tooltip(tester, Icons.chevron_left), 'Zurück zu Spieltag 6');
    expect(_tooltip(tester, Icons.chevron_right), 'Weiter zu Spieltag 8');
  });

  testWidgets('Am Rand bleibt die Richtung übrig, kein leerer Name',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MatchdayStepper(round: 1, onChanged: (_) {}, max: 1),
      ),
    ));

    // Beide Pfeile sind hier abgeblendet. Ein abgeblendeter Knopf wird
    // trotzdem angesagt, also braucht auch er einen Namen.
    expect(_tooltip(tester, Icons.chevron_left), 'Zurück');
    expect(_tooltip(tester, Icons.chevron_right), 'Weiter');
  });
}

String? _tooltip(WidgetTester tester, IconData icon) => tester
    .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
    .tooltip;

/// Index der schließenden Klammer zu der bei [start] geöffneten.
int _endeDesAufrufs(String quelle, int start) {
  var tiefe = 0;
  for (var i = start; i < quelle.length; i++) {
    if (quelle[i] == '(') tiefe++;
    if (quelle[i] == ')') {
      tiefe--;
      if (tiefe == 0) return i;
    }
  }
  return quelle.length - 1;
}
