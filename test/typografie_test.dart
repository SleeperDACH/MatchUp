import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/typografie.dart';

/// **Zwei Regeln zur Schrift, beide schon einmal gebrochen.**
///
/// 1. Schriftgrößen kommen aus der Leiter (`Schrift`). Vorher standen 224
///    hartkodierte Werte in über zwanzig Größen im Code, darunter Halbschritte
///    wie 12,5 · 11,5 · 15,5. Das ergibt keine Hierarchie, die man
///    wiedererkennt, sondern an jeder Stelle eine neue Zahl.
///
/// 2. **Jeder Textstil in einem Theme-Feld nennt die Schriftfamilie.** Ein
///    Stil dort *ersetzt* den aufgelösten Stil, er ergänzt ihn nicht — wer die
///    Familie vergisst, bekommt stumm die Systemschrift. Dreimal passiert: in
///    den Fantasy-Einstellungen (Zeilen in Roboto), in den Reitern (leere
///    Kästchen in der Vorschau) und in `chipTheme`, wo jeder Material-Chip in
///    der falschen Schrift stand, bis es jemand von außen bemerkte.
void main() {
  test('jede Schriftgröße kommt aus der Leiter', () {
    final erlaubt = {...Schrift.alle, ...Schrift.anzeigen};
    final fehler = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final t = f.readAsStringSync();
      for (final m in RegExp(r'fontSize:\s*([0-9.]+)').allMatches(t)) {
        final wert = double.parse(m.group(1)!);
        if (erlaubt.contains(wert)) continue;
        final zeile = '\n'.allMatches(t.substring(0, m.start)).length + 1;
        fehler.add('${f.path.replaceFirst('lib/', '')}:$zeile → $wert');
      }
    }

    expect(fehler, isEmpty,
        reason: '\nDiese Größen stehen nicht in der Leiter:\n'
            '${fehler.join('\n')}\n\n'
            'Erlaubt sind ${Schrift.alle} als Text\n'
            'und ${Schrift.anzeigen} als Anzeigezahlen.\n'
            'Eine neue Stufe gehört nach typografie.dart — mit dem Grund, '
            'warum die vorhandenen nicht reichen.');
  });

  test('jeder Textstil im Theme nennt die Schriftfamilie', () {
    final t = File('lib/app/theme.dart').readAsStringSync();
    final ohne = <int>[];
    for (final m in RegExp(r'TextStyle\(').allMatches(t)) {
      // Bis zur schließenden Klammer lesen, statt eine feste Länge zu raten.
      var tiefe = 0;
      var ende = m.start;
      for (var i = m.start; i < t.length; i++) {
        if (t[i] == '(') tiefe++;
        if (t[i] == ')') {
          tiefe--;
          if (tiefe == 0) {
            ende = i;
            break;
          }
        }
      }
      if (!t.substring(m.start, ende).contains('fontFamily')) {
        ohne.add('\n'.allMatches(t.substring(0, m.start)).length + 1);
      }
    }
    expect(ohne, isEmpty,
        reason: 'theme.dart, Zeile(n) $ohne: TextStyle ohne fontFamily. '
            'Ein Stil in einem Theme-Feld ersetzt den aufgelösten Stil — '
            'ohne Familie steht dort stumm die Systemschrift.');
  });
}
