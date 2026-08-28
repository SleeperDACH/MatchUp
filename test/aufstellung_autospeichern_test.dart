import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/lineup_autosave.dart';

/// Hält den Auto-Speicher der Aufstellung fest. Jeder Fall hier stand einmal
/// für eine Änderung, die wortlos verschwand.
void main() {
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
