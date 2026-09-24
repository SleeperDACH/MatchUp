import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/push/push_einstellungen.dart';

/// **Fehlende Zeile heißt „alles an".**
///
/// Die Regel steht zweimal — in der Datenbank (`push_anlegen`, Migration
/// 0129) und hier. Liefe sie auseinander, zeigte der Einstellungsschirm beim
/// ersten Öffnen sieben ausgeschaltete Schalter, während der Server munter
/// verschickt.
void main() {
  test('ohne gespeicherte Zeile ist alles an', () {
    const e = PushEinstellungen.allesAn();
    for (final k in PushKategorie.alle) {
      expect(e.an(k.schluessel), isTrue, reason: k.schluessel);
    }
  });

  test('eine fehlende Spalte in der Zeile gilt als an', () {
    final e = PushEinstellungen.fromRow({'draft': false});
    expect(e.an('draft'), isFalse);
    expect(e.an('trades'), isTrue);
  });

  test('kopieMit ändert genau einen Schalter', () {
    final e = const PushEinstellungen.allesAn().kopieMit('nachrichten', false);
    expect(e.an('nachrichten'), isFalse);
    expect(e.an('draft'), isTrue);
    expect(e.an('tipps'), isTrue);
  });

  test('toRow schreibt alle Spalten samt Nutzer', () {
    final row = const PushEinstellungen.allesAn()
        .kopieMit('waiver', false)
        .toRow('nutzer-1');
    expect(row['user_id'], 'nutzer-1');
    expect(row['waiver'], isFalse);
    for (final k in PushKategorie.alle) {
      expect(row.containsKey(k.schluessel), isTrue, reason: k.schluessel);
    }
    expect(row['updated_at'], isA<String>());
  });

  test('die Schlüssel stimmen mit der Datenbank überein', () {
    // Dieselbe Liste wie im Check-Constraint von `push_auftraege.kategorie`.
    expect(
      PushKategorie.alle.map((k) => k.schluessel).toList(),
      ['draft', 'trades', 'waiver', 'nachrichten', 'ausfaelle', 'tipps',
       'anfragen'],
    );
  });
}
