import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/home_tip_status.dart';

// „bis wann" auf den Homescreen-Karten: kurz und absolut, damit der Text
// nicht veraltet, während die Karte steht.
void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  // Dienstag, 18. August 2026, 12:00.
  final jetzt = DateTime(2026, 8, 18, 12, 0);

  test('heute: nur die Uhrzeit', () {
    expect(kurzeFrist(DateTime(2026, 8, 18, 20, 30), jetzt), 'bis 20:30');
  });

  test('morgen wird benannt', () {
    expect(kurzeFrist(DateTime(2026, 8, 19, 15, 30), jetzt),
        'bis morgen 15:30');
  });

  test('diese Woche: Wochentag und Uhrzeit', () {
    expect(kurzeFrist(DateTime(2026, 8, 21, 20, 30), jetzt), 'bis Fr., 20:30');
  });

  test('weiter weg: Datum', () {
    expect(kurzeFrist(DateTime(2026, 8, 28, 20, 30), jetzt), 'bis 28.8.');
  });

  test('vorbei ist vorbei', () {
    expect(kurzeFrist(DateTime(2026, 8, 18, 11, 59), jetzt), 'abgelaufen');
  });

  test('Mitternacht heute zählt noch als heute', () {
    expect(kurzeFrist(DateTime(2026, 8, 18, 23, 59), jetzt), 'bis 23:59');
  });
}
