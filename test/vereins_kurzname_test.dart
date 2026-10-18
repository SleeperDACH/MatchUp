import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/logic/vereins_kuerzel.dart';

/// Ein Wort je Verein in Spielpaarungen (auf Ansage, 16.10.2026).
void main() {
  test('die Beispiele aus der Ansage', () {
    expect(vereinsKurzname('Hamburger SV'), 'Hamburg');
    expect(vereinsKurzname('St. Pauli'), 'St. Pauli');
    expect(vereinsKurzname('Nürnberg'), 'Nürnberg');
    expect(vereinsKurzname('FC Köln'), 'Köln');
    expect(vereinsKurzname('Eintracht Frankfurt'), 'Frankfurt');
    expect(vereinsKurzname('FC Bayern München'), 'Bayern');
    expect(vereinsKurzname('Schalke 04'), 'Schalke');
  });

  test('beide Schreibweisen der App treffen denselben Namen', () {
    expect(vereinsKurzname('1. FC Köln'), 'Köln');
    expect(vereinsKurzname('1. FSV Mainz 05'), 'Mainz');
    expect(vereinsKurzname('FSV Mainz 05'), 'Mainz');
    expect(vereinsKurzname('FC Schalke 04'), 'Schalke');
    expect(vereinsKurzname('SV Werder Bremen'), 'Bremen');
    expect(vereinsKurzname('1. FC Union Berlin'), 'Union');
    expect(vereinsKurzname('Borussia Mönchengladbach'), 'Gladbach');
    expect(vereinsKurzname('Bor. Mönchengladbach'), 'Gladbach');
    expect(vereinsKurzname('Bor. Dortmund'), 'Dortmund');
  });

  test('Köln ist nicht gleich Köln', () {
    expect(vereinsKurzname('Viktoria Köln'), 'Viktoria');
    expect(vereinsKurzname('Fortuna Köln'), 'Fortuna');
    expect(vereinsKurzname('Fortuna Düsseldorf'), 'Düsseldorf');
  });

  test('Frauen, zweite Mannschaften, Ziffern im Namen', () {
    expect(vereinsKurzname('Bayer Leverkusen W'), 'Leverkusen');
    expect(vereinsKurzname('Hamburger SV W'), 'Hamburg');
    expect(vereinsKurzname('Hoffenheim II'), 'Hoffenheim II');
    expect(vereinsKurzname('1860 München'), '1860');
  });

  test('Unbekanntes bleibt, wie es ist', () {
    expect(vereinsKurzname('Deutschland'), 'Deutschland');
    expect(vereinsKurzname('Saudi Arabien'), 'Saudi Arabien');
    expect(vereinsKurzname('Bosnien und Herzegowina'), 'Bosnien und Herzegowina');
    expect(vereinsKurzname('Jeddeloh'), 'Jeddeloh');
  });
}
