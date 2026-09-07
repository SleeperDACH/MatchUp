import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/player_absence.dart';

/// **Wer verletzt vom Platz geht, gilt als ausgefallen.**
///
/// Gemeldet: *„Filippo Mane wurde im zweiten Spiel nach 32 Minuten
/// ausgewechselt, mit einer Oberschenkelverletzung. Solche Fehler dürfen nicht
/// passieren. Ich kann nicht bei jedem Spieler manuell nachforschen."*
///
/// Die Ausfallliste der Quelle (`include=sidelined`) kannte ihn nicht. Das war
/// kein Einzelfall: Über die Saison 2026 tragen **neun** Auswechslungen
/// `injured: true`, und **fünf** dieser Spieler standen in keiner Ausfallliste.
///
/// Das Ereignis dagegen steht im selben Abruf, aus dem ohnehin die Punkte
/// kommen. Seit Migration 0122 ist es die zweite Quelle — und der Wortlaut
/// muss den Unterschied tragen: **Eine Beobachtung ist keine Diagnose.**

PlayerAbsence _ausJson(Map<String, dynamic> j) => PlayerAbsence.fromJson(j);

void main() {
  group('gemeldeter Ausfall', () {
    final gemeldet = _ausJson({
      'player_id': 'sportmonks:1',
      'kategorie': 'injury',
      'grund_quelle': 'Hamstring Injury',
      'seit': '2026-08-24',
      'spiele_verpasst': 2,
      'quelle': 'gemeldet',
    });

    test('nennt den Grund im Klartext', () {
      expect(gemeldet.grund, 'Verletzung der hinteren Oberschenkelmuskulatur');
      expect(gemeldet.kopf, 'Verletzt');
      expect(gemeldet.ausgewechselt, isFalse);
    });

    test('eine Sperre bleibt eine Sperre', () {
      final s = _ausJson({
        'player_id': 'sportmonks:2',
        'kategorie': 'suspended',
        'grund_quelle': 'Red Card Suspension',
        'quelle': 'gemeldet',
      });
      expect(s.kopf, 'Gesperrt');
      expect(s.gesperrt, isTrue);
    });
  });

  group('zwei Einträge, einer wird gezeigt', () {
    // Gemeldet: „Prass zeigt auch falsche Verletzung an." Die Quelle schließt
    // einen Eintrag oft nicht, wenn ein neuer dazukommt — er trug „Ill" seit
    // dem 23.01.2025 mit 64 verpassten Spielen **und** „Adductor Pain" seit
    // dem 21.08.2026. Bis hierher entschied die Reihenfolge der Zeilen.
    PlayerAbsence a({
      required String grund,
      required String seit,
      bool gesperrt = false,
    }) =>
        _ausJson({
          'player_id': 'sportmonks:31626002',
          'kategorie': gesperrt ? 'suspended' : 'injury',
          'grund_quelle': grund,
          'seit': seit,
        });

    final alt = a(grund: 'Ill', seit: '2025-01-23');
    final neu = a(grund: 'Adductor Pain', seit: '2026-08-21');

    test('der jüngere Eintrag gewinnt', () {
      expect(neu.schlaegt(alt), isTrue);
      expect(alt.schlaegt(neu), isFalse);
    });

    test('und zwar unabhängig von der Reihenfolge', () {
      // Genau daran hing der Fehler: Ohne Regel entschied, welche Zeile
      // zuerst kam.
      for (final reihenfolge in [
        [alt, neu],
        [neu, alt],
      ]) {
        PlayerAbsence? gewaehlt;
        for (final e in reihenfolge) {
          if (gewaehlt == null || e.schlaegt(gewaehlt)) gewaehlt = e;
        }
        expect(gewaehlt!.grund, 'Adduktorenbeschwerden');
      }
    });

    test('die Sperre schlägt auch eine jüngere Verletzung', () {
      // Wer gesperrt ist, spielt auch gesund nicht — und die Sperre endet an
      // einem bekannten Tag.
      final sperre = a(
          grund: 'Red Card Suspension', seit: '2026-08-30', gesperrt: true);
      final juengereVerletzung = a(grund: 'Knock', seit: '2026-09-05');
      expect(sperre.schlaegt(juengereVerletzung), isTrue);
      expect(juengereVerletzung.schlaegt(sperre), isFalse);
    });

    test('ohne Datum verliert ein Eintrag', () {
      final ohne = a(grund: 'Knock', seit: '');
      expect(ohne.schlaegt(neu), isFalse);
      expect(neu.schlaegt(ohne), isTrue);
    });
  });

  group('beobachteter Ausfall', () {
    // Genau der gemeldete Fall: Hoffenheim gegen Dortmund, 2. Spieltag.
    final mane = _ausJson({
      'player_id': 'sportmonks:37602269',
      'kategorie': 'injury',
      'grund_quelle': 'Substituted Off Injured',
      'seit': '2026-09-05',
      'quelle': 'ausgewechselt',
      'runde': 2,
      'minute': 32,
    });

    test('sagt, was man weiß — Spieltag und Minute', () {
      expect(mane.ausgewechselt, isTrue);
      expect(mane.grund, 'Verletzt ausgewechselt in der 32. Minute am 2. Spieltag');
    });

    test('behauptet keine Diagnose', () {
      // „Verletzt" wäre eine Aussage, die niemand getroffen hat: Das Ereignis
      // sagt, dass er verletzt vom Platz ging, nicht dass er ausfällt.
      expect(mane.kopf, 'Vermutlich verletzt');
      expect(mane.kopf, isNot('Verletzt'));
    });

    test('in engen Zeilen steht „angeschlagen", nicht „verletzt"', () {
      // Die Free Agency hat neben Verein und Punkten Platz für ein Wort. Dort
      // ist „verletzt" eine Behauptung zu viel — genau an der Stelle, an der
      // man jemanden holt oder liegen lässt.
      expect(mane.kurz, 'angeschlagen');
      final gemeldet = _ausJson({
        'player_id': 'sportmonks:9',
        'kategorie': 'injury',
        'grund_quelle': 'Knee Injury',
        'quelle': 'gemeldet',
      });
      expect(gemeldet.kurz, 'verletzt');
    });

    test('der englische Wortlaut der Quelle steht nie auf dem Schirm', () {
      // Sonst stünde dort „Substituted Off Injured" — die Sentinel-Zeichenkette
      // aus der Sicht, nicht für Leser gedacht.
      expect(mane.grund, isNot(contains('Substituted')));
    });

    test('ohne Minute und Runde bleibt der Satz lesbar', () {
      final knapp = _ausJson({
        'player_id': 'sportmonks:3',
        'kategorie': 'injury',
        'grund_quelle': 'Substituted Off Injured',
        'quelle': 'ausgewechselt',
      });
      expect(knapp.grund, 'Verletzt ausgewechselt');
    });
  });
}
