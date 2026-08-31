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
      // Ligapunkte aus Siegen und Unentschieden — ein `int`.
      'record.points',
      // Die Summe der Kader-Limits: Plätze, keine Punkte.
      r'$summe',
      // Anzahl Spieltage der regulären Saison.
      'plan.totalMatchdays',
      // Gesamtzahl der Draft-Picks (`managers.length * roundsThisPhase`) —
      // ein `int`, kein Score. Der erweiterte Wächter hat sie beim ersten
      // Durchlauf gefunden; sie steht hier, damit die Empfindlichkeit nicht
      // wieder zurückgedreht wird.
      r'$total',
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
          // Drei Schreibweisen, drei Anläufe: „points" fing die erste Runde,
          // „pts" die Zelle im MatchUp — und `scorePlayer(...)` die
          // Leistungstabelle im Spielerprofil, die ihre Punkte direkt aus der
          // Wertungsfunktion interpolierte. Wer so einen Wächter schreibt,
          // sollte über seine Namensannahme dreimal nachdenken.
          // **Vierter Anlauf, und diesmal nicht wieder ein Name mehr.**
          // Nacheinander sind durchgerutscht: `points` (Team der Woche),
          // `pts` (Zelle im MatchUp), `scorePlayer(...)` (Leistungstabelle im
          // Profil) — und zuletzt `homeTotal`/`awayTotal` im
          // MatchUp-Detailkopf, wo `221.10000000000002` stand.
          //
          // Die Namensannahme war jedes Mal das Problem. Deshalb prüft der
          // Wächter jetzt auf eine **Wortfamilie** statt auf drei Wörter:
          // alles, was nach einer Punktzahl klingt. Er wird dadurch
          // empfindlicher — und das ist der Punkt. Wer eine Zahl so nennt und
          // sie roh interpoliert, soll erklären müssen, warum sie kein
          // `double` ist; dafür steht die Ausnahmeliste oben.
          final klein = ausdruck.toLowerCase();
          // **Fünfte Erweiterung, fünfter Durchrutscher.** Zuletzt `margin` —
          // der Vorsprung eines Duells ist ein `double`, klingt aber nicht nach
          // Punkten. Diese Wache rät Namen und ist nur so gut wie die Fantasie
          // ihres Autors; die verlässliche liest den fertigen Schirm
          // (`nachkommastellen_test.dart`).
          final klingtNachPunkten = RegExp(
                  r'points?\b|\bpts\b|punkte|\bpkt|total|score(?!board)|summe'
                  r'|margin|vorsprung|abstand|schnitt|\bdelta\b')
              .hasMatch(klein);
          if (!klingtNachPunkten) continue;
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
