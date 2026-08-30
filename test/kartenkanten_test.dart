import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Eine Kante für alle Karten.**
///
/// Auf der Liga-Übersicht standen drei Sorten Karten untereinander, und jede
/// fasste ihre Kante anders: roter Rand am MatchUp-Kasten, goldener Rand auf
/// goldener Fläche am Rückblick, graue Haarlinie an den Zeilengruppen. Auf
/// dunklem Grund entsteht Tiefe über die **Fläche**, nicht über die Kante.
///
/// Der Test liest `lib/` und sucht **kartenähnliche** Ränder mit Farbe: ein
/// `Border.all`, dessen Farbe weder `dividerColor` noch `outlineVariant` ist,
/// in einer Dekoration mit merklich runden Ecken (ab Radius 14). Kleine
/// Elemente — Chips, Pillen, Avatare, Ringe — fallen darunter heraus; die
/// dürfen Farbe tragen.
///
/// **Jede verbleibende Stelle steht hier namentlich mit Grund.** Kommt eine
/// dazu, wird der Test rot, und wer sie einträgt, muss sagen warum. Das ist
/// dasselbe Muster wie bei `punkte_formatierung_test.dart` — es hat sich als
/// das einzige erwiesen, das eine Stilregel über Monate hält.
void main() {
  /// Datei -> (erlaubte Anzahl, Grund).
  ///
  /// Farbe an einer Kante ist erlaubt, wo sie einen **Zustand** trägt: etwas
  /// wartet, etwas ist ausgewählt, etwas ist kaputt. Nicht erlaubt ist sie als
  /// Schmuck an einem Behälter.
  const erlaubt = <String, (int, String)>{
    'app/home_screen.dart': (
      1,
      'Leerzustand „Liga erstellen": eine Einladung, keine Fläche — sie trägt '
          'die Farbe des Bereichs, in den sie führt (bewusst so entschieden, '
          'nachdem der Schirm als „trostlos" gemeldet worden war).'
    ),
    'core/ui/league_chat.dart': (
      1,
      'Systemnachricht im Chat: eine Ansage, keine Karte.'
    ),
    'features/fantasy/ui/draft_room_screen.dart': (
      1,
      'Auto-Pick-Warnung — hier ist etwas kaputt, und das darf man sehen.'
    ),
    'features/fantasy/ui/lineup_screen.dart': (
      2,
      'Spieler-Slot auf dem Feld (Positionsfarbe) und der Free-Agency-Chip; '
          'beides Zustand bzw. Chip, keine Karte.'
    ),
    'features/fantasy/ui/matchup_hero.dart': (
      1,
      'Element auf dem grünen Rasen, nicht auf Kartengrund — dort ist die '
          'helle Kante die einzige, die sich abhebt.'
    ),
    'features/fantasy/ui/player_action_buttons.dart': (
      1,
      'Die Blöcke „Kommt rein" und „wer macht Platz?" im Bestätigungsblatt: '
          'Grün und Rot sagen die Richtung, das ist der Inhalt.'
    ),
    'features/fantasy/ui/trade_screen.dart': (
      1,
      'Derselbe Block im Trade-Schirm, aus demselben Grund.'
    ),
    'features/fantasy/ui/spieler_kachel.dart': (
      1,
      'Auswahl-Hervorhebung der Spielerkachel — ein Zustand.'
    ),
    'features/fantasy/ui/weekly_recap_screen.dart': (
      1,
      'Hervorgehobene Zeile im Rückblick (Team der Woche) — ein Zustand.'
    ),
  };

  test('keine farbigen Kanten an Karten', () {
    final gefunden = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final t = f.readAsStringSync();
      for (final m in RegExp(r'Border\.all\(').allMatches(t)) {
        final vor = t.substring(
            (m.start - 420).clamp(0, t.length), m.start);
        final nach =
            t.substring(m.start, (m.start + 200).clamp(0, t.length));
        if (nach.contains('dividerColor') || nach.contains('outlineVariant')) {
          continue;
        }
        final radien = RegExp(r'BorderRadius\.circular\((\d+)')
            .allMatches(vor)
            .map((r) => int.parse(r.group(1)!))
            .toList();
        if (radien.isEmpty) continue;
        // Der letzte Radius vor der Kante gehört zu derselben Dekoration.
        if (radien.last < 14) continue;
        final pfad = f.path.replaceFirst('lib/', '');
        gefunden[pfad] = (gefunden[pfad] ?? 0) + 1;
      }
    }

    final fehler = <String>[];
    gefunden.forEach((pfad, anzahl) {
      final e = erlaubt[pfad];
      if (e == null) {
        fehler.add('$pfad: $anzahl farbige Kartenkante(n), nicht eingetragen.\n'
            '    Entweder die Haarlinie (Theme.of(context).dividerColor) '
            'benutzen und die Farbe als Hauch aus der Ecke tragen —\n'
            '    oder hier mit Begründung eintragen, falls sie einen Zustand '
            'anzeigt.');
      } else if (anzahl != e.$1) {
        fehler.add('$pfad: $anzahl statt ${e.$1} erwartet.\n'
            '    Bisheriger Grund: ${e.$2}');
      }
    });
    // Eingetragene Stellen, die es nicht mehr gibt, sollen auch auffallen —
    // sonst wächst die Liste und niemand räumt sie.
    for (final pfad in erlaubt.keys) {
      if (!gefunden.containsKey(pfad)) {
        fehler.add('$pfad steht in der Liste, hat aber keine farbige '
            'Kartenkante mehr — Eintrag entfernen.');
      }
    }

    expect(fehler, isEmpty, reason: '\n${fehler.join('\n')}');
  });
}
