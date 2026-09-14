import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/tippspiel/logic/nachtrag.dart';

/// **Ein Speichern für den ganzen Spieltag.**
///
/// Gemeldet: „Wenn man im Tippspiel nachträgliche Tipps nachträgt, muss man
/// jedes einzelne speichern können." Neun Knöpfe je Bundesliga-Spieltag.
///
/// Mit einem Knopf wird die Frage „was geht überhaupt an den Server?" zu einer
/// Entscheidung, die man prüfen muss — vorher war sie trivial („die eine, auf
/// die du getippt hast"). Jeder Fall hier ist ein Tipp, der sonst still
/// verloren ginge oder still erfunden würde.
NachtragZeile _z(String id, String h, String a, {int? vh, int? va}) =>
    NachtragZeile(
        fixtureId: id, heim: h, gast: a, vorherHeim: vh, vorherGast: va);

void main() {
  group('pruefeNachtrag', () {
    test('nimmt nur vollständig ausgefüllte Zeilen', () {
      final p = pruefeNachtrag([
        _z('a', '2', '1'),
        _z('b', '', ''),
        _z('c', '0', '0'),
      ]);
      expect(p.zuSpeichern.map((t) => t.fixtureId), ['a', 'c']);
      expect(p.hatFehler, isFalse);
    });

    test('eine leere Zeile ist kein 0:0', () {
      // **Leer heißt „nicht getippt".** Würde sie als 0:0 durchgehen, bekäme
      // das Mitglied Tipps, die niemand abgegeben hat — und bei richtiger
      // Tendenz sogar Punkte dafür.
      final p = pruefeNachtrag([_z('a', '', '')]);
      expect(p.zuSpeichern, isEmpty);
      expect(p.hatFehler, isFalse);
    });

    test('eine halbe Zeile ist ein Fehler, kein Überspringen', () {
      // Wer neun Spiele tippt und bei einem die zweite Zahl vergisst, bekäme
      // sonst ein stilles „gespeichert" und einen fehlenden Tipp.
      final p = pruefeNachtrag([
        _z('a', '2', '1'),
        _z('b', '3', ''),
        _z('c', '', '1'),
      ]);
      expect(p.halbeZeilen, ['b', 'c']);
      expect(p.hatFehler, isTrue);
      // Die gültige Zeile steht trotzdem bereit — der Schirm entscheidet, ob
      // er sie schickt. Er tut es nicht, solange ein Fehler dabei ist.
      expect(p.zuSpeichern.map((t) => t.fixtureId), ['a']);
    });

    test('unveränderte Zeilen werden nicht noch einmal geschrieben', () {
      final p = pruefeNachtrag([
        _z('a', '2', '1', vh: 2, va: 1),
        _z('b', '2', '1', vh: 1, va: 1),
      ]);
      expect(p.zuSpeichern.map((t) => t.fixtureId), ['b']);
      expect(p.unveraendert, 1);
    });

    test('ohne Änderung gibt es nichts zu tun', () {
      final p = pruefeNachtrag([_z('a', '2', '1', vh: 2, va: 1)]);
      expect(p.gibtEsWasZuTun, isFalse);
    });

    test('ein vorhandener Tipp lässt sich überschreiben', () {
      final p = pruefeNachtrag([_z('a', '3', '0', vh: 2, va: 1)]);
      expect(p.zuSpeichern.single, (fixtureId: 'a', home: 3, away: 0));
    });

    test('Leerzeichen zählen nicht als Eingabe', () {
      final p = pruefeNachtrag([_z('a', '  ', ' ')]);
      expect(p.zuSpeichern, isEmpty);
      expect(p.hatFehler, isFalse);
    });
  });
}
