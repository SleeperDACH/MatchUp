import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/widgets/now_card.dart';

// Restzeit-Text der Jetzt-Karte: je näher die Deadline, desto genauer.
void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  final now = DateTime(2026, 8, 18, 12, 0);

  test('unter einer Stunde: Minuten und Sekunden', () {
    expect(formatDeadline(now.add(const Duration(minutes: 7, seconds: 5)), now),
        'Anstoß in 7:05 min');
  });

  test('unter einem Tag: Stunden und Minuten', () {
    expect(formatDeadline(now.add(const Duration(hours: 5, minutes: 3)), now),
        'Anstoß in 5:03 Std');
  });

  test('unter einer Woche: Wochentag und Uhrzeit', () {
    expect(formatDeadline(now.add(const Duration(days: 3, hours: 3)), now),
        'Anstoß Fr., 15:00 Uhr');
  });

  test('weiter weg: mit Datum', () {
    expect(formatDeadline(DateTime(2026, 8, 28, 20, 30), now),
        'Anstoß Fr., 28. Aug., 20:30');
  });

  test('Pick-Uhr zählt nur die Restzeit, ohne Anstoß-Bezug', () {
    expect(
        formatDeadline(now.add(const Duration(seconds: 42)), now, isPick: true),
        'noch 0:42 min');
  });

  test('abgelaufen: Anpfiff bzw. Zeit abgelaufen', () {
    final vorbei = now.subtract(const Duration(minutes: 1));
    expect(formatDeadline(vorbei, now), 'Anpfiff');
    expect(formatDeadline(vorbei, now, isPick: true), 'Zeit abgelaufen');
  });
}
