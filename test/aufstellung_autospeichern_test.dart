import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/lineup_autosave.dart';

/// Hält den Auto-Speicher der Aufstellung fest. Jeder Fall hier stand einmal
/// für eine Änderung, die wortlos verschwand.
void main() {
  _fehlerfall();
  group('Auto-Speichern der Aufstellung', () {
    test('gültige Elf, nichts unterwegs, Spieltag bekannt → speichern', () {
      expect(
        naechsterSpeicherSchritt(
            gueltig: true, laeuftGerade: false, spieltag: 1),
        SpeicherSchritt.speichern,
      );
    });

    test('läuft schon ein Speichern → erneut versuchen, nicht verwerfen', () {
      // Vorher fiel die *neuere* Änderung hier lautlos weg: Zwei Züge kurz
      // hintereinander, und der zweite kam nie an.
      expect(
        naechsterSpeicherSchritt(
            gueltig: true, laeuftGerade: true, spieltag: 1),
        SpeicherSchritt.spaeterErneut,
      );
    });

    test('Spieltag noch nicht geladen → warten statt raten', () {
      // Der frühere Notnagel `?? 34` hat eine Aufstellung nachweislich auf
      // Spieltag 34 geschrieben — angenommen, unsichtbar, ohne Fehler.
      expect(
        naechsterSpeicherSchritt(
            gueltig: true, laeuftGerade: false, spieltag: null),
        SpeicherSchritt.spaeterErneut,
      );
    });

    test('unvollständige Elf → nichts senden, aber melden', () {
      expect(
        naechsterSpeicherSchritt(
            gueltig: false, laeuftGerade: false, spieltag: 1),
        SpeicherSchritt.unvollstaendig,
      );
    });

    test('unterwegs schlägt unvollständig — sonst ginge der Nachzügler verloren',
        () {
      expect(
        naechsterSpeicherSchritt(
            gueltig: false, laeuftGerade: true, spieltag: 1),
        SpeicherSchritt.spaeterErneut,
      );
    });
  });
}

/// **Nach einem Fehlschlag wird weiterversucht — und die Fußzeile sagt es.**
///
/// Gemeldet: *„Während des letzten Spieltages gab es häufiger Speicherprobleme
/// bei der Aufstellung."* Der Fehlschlag war der einzige Ausgang ohne zweiten
/// Versuch: `laeuftGerade` bestellte sich neu ein, ein fehlender Spieltag
/// auch — nur der Netzfehler zeigte eine Snackbar und war fertig.
void _fehlerfall() {
  group('nach einem Fehlschlag', () {
    test('wächst der Abstand und ist bei 30 s gedeckelt', () {
      expect(wartezeitNachFehler(0), Duration.zero);
      expect(wartezeitNachFehler(1), const Duration(seconds: 2));
      expect(wartezeitNachFehler(2), const Duration(seconds: 4));
      expect(wartezeitNachFehler(3), const Duration(seconds: 8));
      expect(wartezeitNachFehler(4), const Duration(seconds: 16));
      expect(wartezeitNachFehler(5), const Duration(seconds: 30));
      // Auch nach einer langen Funkloch-Fahrt bleibt es eine sinnvolle Dauer.
      expect(wartezeitNachFehler(500), const Duration(seconds: 30));
      expect(wartezeitNachFehler(500).isNegative, isFalse);
    });

    test('sagt die Fußzeile etwas anderes als „Speichere …"', () {
      expect(
        speicherAnzeige(
            gueltig: true, laeuftGerade: false, offen: true, fehlversuche: 1),
        SpeicherAnzeige.fehlgeschlagen,
      );
      expect(
        speicherAnzeige(
            gueltig: true, laeuftGerade: true, offen: true, fehlversuche: 0),
        SpeicherAnzeige.laeuft,
      );
      expect(
        speicherAnzeige(
            gueltig: true, laeuftGerade: false, offen: false, fehlversuche: 0),
        SpeicherAnzeige.gespeichert,
      );
      // Eine unvollständige Elf schlägt alles: Sie *kann* nicht gespeichert
      // werden, ein Wiederholversuch wäre die falsche Auskunft.
      expect(
        speicherAnzeige(
            gueltig: false, laeuftGerade: false, offen: true, fehlversuche: 3),
        SpeicherAnzeige.unvollstaendig,
      );
    });
  });
}
