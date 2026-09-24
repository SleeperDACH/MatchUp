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
/// in einer Dekoration mit merklich runden Ecken (ab Radius 12). Kleine
/// Elemente — Chips, Pillen, Avatare, Ringe — fallen darunter heraus; die
/// dürfen Farbe tragen.
///
/// **Die Schwelle stand auf 14 und war damit zu grob.** Gemeldet am
/// 08.09.2026: die goldene Umrandung im Aufstellungsreiter und die Kacheln
/// der Liga-Übersicht — beide Radius 12, beide über die volle Breite, beide
/// eindeutig Karten, und alle vom Wächter nie gesehen. Ein Kasten ist keine
/// Pille, nur weil seine Ecken zwei Punkte weniger rund sind.
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
      4,
      'Spieler-Slot auf dem Feld, der Free-Agency-Chip und die beiden '
          'Ablegeflächen beim Ziehen: alles Zustände („gewählt", „hier '
          'loslassen"), keine Karten.\n'
          '    Nicht mitgezählt und bewusst so: der Strich in der '
          'Positionsfarbe über dem Namensfeld der Spielerkachel (Ansage vom '
          '17.09.2026). Er ist ein `Border(top: …)` ohne eigenen Radius und '
          'fällt damit nicht unter die Regel — sie meint den Rahmen **um** '
          'einen Behälter, nicht eine Trennlinie **in** ihm. Die Kachel selbst '
          'ist schwarz und deckend; die erste Fassung färbte das ganze '
          'Namensband ein und wurde als „sehr, sehr bunt" zurückgewiesen.'
    ),
    'app/live_screen.dart': (
      1,
      'Der heutige Tag in der Tagesleiste — ein Zustand an einer Zelle, keine '
          'Karte.'
    ),
    'core/ui/form_section.dart': (
      1,
      '`FormError` — hier ist etwas kaputt, und das darf man sehen.'
    ),
    'features/fantasy/ui/roster_limit_banner.dart': (
      1,
      'Der Kader liegt über einem Limit — dieselbe Sorte wie `FormError`.'
    ),
    'features/fantasy/ui/playoff_bracket_screen.dart': (
      1,
      'Die eigene Zeile im Baum — ein Zustand. **Sie trägt dafür noch Grün**, '
          'während Tabelle und Navileiste „das bist du" längst hell sagen; '
          'wer den Baum das nächste Mal anfasst, zieht das mit.'
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
      2,
      'Der Richtungsblock („Kommt rein" / „wer macht Platz?"), und die Hülle '
          'der Angebotskarte: Ein eingehendes, offenes Angebot will etwas von '
          'mir und trägt dafür Hauch **und** getönte Kante. Die Kante ist der '
          'Teil, der zur Regel quer steht — wer die Karte das nächste Mal '
          'anfasst, lässt sie weg; der Hauch sagt es schon.'
    ),
    'core/ui/option_tile.dart': (
      1,
      'Die ausgewählte Option — ein Zustand, dieselbe Sorte wie `PillChip`.'
    ),
    'features/fantasy/ui/fantasy_league_screen.dart': (
      1,
      'Die Kachel mit rotem Zähler: Hier wartet etwas, und die rote Kante '
          'trägt genau das. Ohne Zähler ist es die gewöhnliche Haarlinie.'
    ),
    // `app/widgets/navi_kapsel.dart` stand hier für die Marke um den aktiven
    // Reiter. **Die gibt es seit dem 17.09.2026 nicht mehr** (Ansage: „Können
    // wir in der Leiste diese Umrandung rausnehmen?"): Den Zustand tragen
    // jetzt das hellere Symbol und das Wort, das nur unter dem aktiven Reiter
    // steht. Ohne Kante kein Eintrag — der Test verlangt das Aufräumen selbst,
    // sonst wächst die Liste und niemand räumt sie.
    'features/fantasy/ui/spieler_kachel.dart': (
      1,
      'Auswahl-Hervorhebung der Spielerkachel — ein Zustand.'
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
        // **Neutral zählt nur, wenn es unbedingt gilt.** Die Prüfung sah
        // vorher bloß nach, ob irgendwo im Umfeld `dividerColor` oder
        // `outlineVariant` steht — und übersah damit jede Kante, deren Farbe
        // in einer Bedingung steckt. Genau so ist der grüne Rahmen im
        // MatchUp jahrelang durchgerutscht: „grün, wenn dieser Spieler
        // führt, sonst outlineVariant". Der neutrale Zweig machte die ganze
        // Stelle unsichtbar.
        final neutral =
            nach.contains('dividerColor') || nach.contains('outlineVariant');
        if (neutral && !nach.substring(0, nach.indexOf(')') + 1).contains('?')) {
          continue;
        }
        final radien = RegExp(r'BorderRadius\.circular\((\d+)')
            .allMatches(vor)
            .map((r) => int.parse(r.group(1)!))
            .toList();
        if (radien.isEmpty) continue;
        // Der letzte Radius vor der Kante gehört zu derselben Dekoration.
        if (radien.last < 12) continue;
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
