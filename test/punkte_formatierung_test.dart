import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';

/// Fantasy-Punkte sind `double`, und die Wertung kennt 0,4 je Klärung und
/// −0,4 je Foul. `0.4` ist binär nicht exakt darstellbar: Summiert man genug
/// davon, steht am Ende `12.100000000000001`. Genau so stand es im „Team der
/// Woche" auf dem Schirm.
///
/// Deshalb zwei Prüfungen: dass [formatPoints] das abfängt — und dass niemand
/// wieder daran vorbei rendert.
void main() {
  group('formatPoints', () {
    test('fängt den Fließkomma-Rest ab', () {
      // So entsteht er wirklich: dreißig Klärungen à 0,4.
      var summe = 0.0;
      for (var i = 0; i < 30; i++) {
        summe += 0.4;
      }
      expect(summe.toString(), contains('000000'),
          reason: 'Sonst wäre der Test wertlos — der Rest muss da sein.');
      expect(formatPoints(summe), '12');
    });

    test('ganze Zahlen ohne Komma, halbe mit', () {
      expect(formatPoints(16), '16');
      expect(formatPoints(1.5), '1,5');
      expect(formatPoints(-0.4), '-0,4');
    });

    test('rundet auf eine Stelle — mehr kann die Wertung nicht erzeugen', () {
      // Alle Werte sind Vielfache von 0,1; Summen davon auch.
      expect(formatPoints(12.04), '12');
      expect(formatPoints(12.06), '12,1');
    });
  });

  test('kein roher double landet in einem Text', () {
    // Ausnahmen mit Grund — beides sind `int`, keine Fantasy-Scores.
    const erlaubt = {
      // Ligapunkte aus Siegen und Unentschieden.
      'record.points',
    };

    final klammer = RegExp(r'\$\{[^}]*\}');
    final einfach = RegExp(r'\$[A-Za-z_]\w*');
    final treffer = <String>[];

    for (final f in Directory('lib/features/fantasy/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final zeilen = f.readAsLinesSync();
      for (var i = 0; i < zeilen.length; i++) {
        final zeile = zeilen[i];
        if (zeile.trimLeft().startsWith('//')) continue;
        for (final m in [
          ...klammer.allMatches(zeile),
          ...einfach.allMatches(zeile),
        ]) {
          final ausdruck = m.group(0)!;
          // Auch die Kurzform: In `matchup_lineups.dart` hieß die Variable
          // `pts`, und genau deshalb ist dort eine rohe Interpolation
          // monatelang durchgerutscht.
          final klein = ausdruck.toLowerCase();
          if (!klein.contains('points') &&
              !RegExp(r'\bpts\b').hasMatch(klein)) {
            continue;
          }
          if (ausdruck.contains('formatPoints(')) continue;
          if (erlaubt.any(ausdruck.contains)) continue;
          treffer.add('${f.path}:${i + 1}  $ausdruck');
        }
      }
    }

    expect(treffer, isEmpty,
        reason: 'Punkte gehören durch formatPoints(), sonst steht der '
            'Fließkomma-Rest auf dem Schirm:\n${treffer.join('\n')}');
  });
}
