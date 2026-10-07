import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/push/push_einstellungen.dart';

/// **Fehlende Zeile heißt „alles an".**
///
/// Die Regel steht zweimal — in der Datenbank (`push_anlegen`, Migration
/// 0131) und hier. Liefe sie auseinander, zeigte der Einstellungsschirm beim
/// ersten Öffnen lauter ausgeschaltete Schalter, während der Server munter
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
    final e = const PushEinstellungen.allesAn().kopieMit('liga_chat', false);
    expect(e.an('liga_chat'), isFalse);
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
    // Dieselbe Liste wie die Spalten von `push_einstellungen` und der Check
    // von `push_auftraege.kategorie` (Migration 0131), ohne die beiden
    // Altsorten `nachrichten` und `anfragen`.
    expect(
      PushKategorie.alle.map((k) => k.schluessel).toList(),
      [
        'draft', 'trades', 'waiver', 'ausfaelle', 'liga_chat', 'liga_anfragen',
        'tipps', 'runden_chat', 'runden_anfragen',
        'live_anpfiff', 'live_tore', 'live_rote_karten', 'live_halbzeit',
        'live_endstand',
        'direktnachrichten', 'freunde',
      ],
    );
  });

  test('jeder Bereich hat Schalter, und keiner fehlt', () {
    for (final b in PushBereich.values) {
      expect(PushKategorie.imBereich(b), isNotEmpty, reason: b.name);
    }
    final summe = PushBereich.values
        .map((b) => PushKategorie.imBereich(b).length)
        .fold(0, (a, n) => a + n);
    expect(summe, PushKategorie.alle.length);
  });

  test('die Altsorten aus 0129 stehen nicht mehr auf dem Schirm', () {
    final schluessel = PushKategorie.alle.map((k) => k.schluessel).toSet();
    expect(schluessel.contains('nachrichten'), isFalse);
    expect(schluessel.contains('anfragen'), isFalse);
  });
}
