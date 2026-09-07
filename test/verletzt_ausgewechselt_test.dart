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
