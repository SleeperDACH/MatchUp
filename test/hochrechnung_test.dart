import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/hochrechnung.dart';

void main() {
  final anpfiff = DateTime(2026, 10, 17, 15, 30);

  test('vor dem Anpfiff ist die Hochrechnung die Summe der Schnitte', () {
    final h = hochrechnung([
      const HochrechnungsPosten(lage: SpielLage.offen, punkte: 0, schnitt: 10),
      const HochrechnungsPosten(lage: SpielLage.offen, punkte: 0, schnitt: 6),
    ], jetzt: anpfiff);
    expect(h.stand, 0);
    expect(h.erwartet, 16);
    expect(h.offenAnteil, 1);
  });

  test('fertig zählt echt, offen mit Schnitt, laufend anteilig', () {
    final h = hochrechnung([
      // Fertig: 14 echte Punkte, egal wie hoch der Schnitt ist.
      const HochrechnungsPosten(lage: SpielLage.fertig, punkte: 14, schnitt: 8),
      // Noch nicht dran: sein Schnitt.
      const HochrechnungsPosten(lage: SpielLage.offen, punkte: 0, schnitt: 9),
      // Läuft seit 75 Uhrminuten = Spielminute 60: 4 echte plus ein Drittel
      // von 9.
      HochrechnungsPosten(
        lage: SpielLage.laeuft,
        punkte: 4,
        schnitt: 9,
        anpfiff: anpfiff,
      ),
    ], jetzt: anpfiff.add(const Duration(minutes: 75)));
    expect(h.stand, 18);
    expect(h.offen, closeTo(9 + 3, 1e-9));
    expect(h.erwartet, closeTo(30, 1e-9));
  });

  test('ein Ausfall ohne Anpfiff bringt nichts', () {
    final h = hochrechnung([
      const HochrechnungsPosten(
          lage: SpielLage.offen, punkte: 0, schnitt: 12, faellt: true),
    ], jetzt: anpfiff);
    expect(h.erwartet, 0);
  });

  test('die Spielminute zieht die Halbzeit ab und endet bei 90', () {
    expect(geschaetzteMinute(anpfiff, anpfiff), 0);
    expect(geschaetzteMinute(anpfiff, anpfiff.add(const Duration(minutes: 30))),
        30);
    // In der Pause bleibt die Uhr bei 45.
    expect(geschaetzteMinute(anpfiff, anpfiff.add(const Duration(minutes: 55))),
        45);
    expect(geschaetzteMinute(anpfiff, anpfiff.add(const Duration(minutes: 80))),
        65);
    expect(geschaetzteMinute(anpfiff, anpfiff.add(const Duration(hours: 3))),
        90);
  });

  group('Siegchance während des Spieltags', () {
    Hochrechnung h(double stand, double offen, double voll) => Hochrechnung(
        stand: stand, erwartet: stand + offen, offen: offen, voll: voll);

    test('je weniger offen ist, desto deutlicher dieselbe Differenz', () {
      final frueh = siegchanceLive(
          heim: h(10, 90, 100), gast: h(5, 85, 100), wochenStreuung: 30)!;
      final spaet = siegchanceLive(
          heim: h(95, 5, 100), gast: h(85, 5, 100), wochenStreuung: 30)!;
      // Beide Male 10 Punkte Vorsprung in der Erwartung.
      expect(frueh, greaterThan(0.5));
      expect(spaet, greaterThan(frueh));
    });

    test('ist alles gespielt, steht es fest', () {
      expect(
          siegchanceLive(
              heim: h(120, 0, 100), gast: h(90, 0, 100), wochenStreuung: 30),
          1);
      expect(
          siegchanceLive(
              heim: h(80, 0, 100), gast: h(90, 0, 100), wochenStreuung: 30),
          0);
      expect(
          siegchanceLive(
              heim: h(90, 0, 100), gast: h(90, 0, 100), wochenStreuung: 30),
          0.5);
    });

    test('ohne gemessene Streuung keine Zahl, solange etwas offen ist', () {
      expect(
          siegchanceLive(
              heim: h(10, 50, 60), gast: h(5, 50, 55), wochenStreuung: null),
          isNull);
    });
  });
}
