import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/push/push_dienst.dart';

/// **Was aus einer Benachrichtigung ankommt, ist Fremdtext.**
///
/// FCM reicht `data` als Zeichenketten durch — was dort steht, hat den Weg
/// über Google genommen und kann alt, leer oder fremd sein. Die App darf
/// daran nicht scheitern: unbekannte Art oder fehlende ID heißt „nichts
/// öffnen", nicht „abstürzen".
void main() {
  test('vollständiges Ziel wird gelesen', () {
    final ziel = PushZiel.ausDaten({
      'art': 'fantasy',
      'id': 'abc-123',
      'kategorie': 'draft',
    });
    expect(ziel, isNotNull);
    expect(ziel!.art, 'fantasy');
    expect(ziel.id, 'abc-123');
    expect(ziel.kategorie, 'draft');
  });

  test('fehlende Kategorie ist erlaubt', () {
    final ziel = PushZiel.ausDaten({'art': 'tipprunde', 'id': 'r1'});
    expect(ziel, isNotNull);
    expect(ziel!.kategorie, '');
  });

  test('unbekannte Art öffnet nichts', () {
    expect(PushZiel.ausDaten({'art': 'raumschiff', 'id': 'r1'}), isNull);
  });

  test('leere ID öffnet nichts', () {
    expect(PushZiel.ausDaten({'art': 'fantasy', 'id': ''}), isNull);
    expect(PushZiel.ausDaten(const {}), isNull);
  });

  test('alle Arten, die der Server schickt, sind bekannt', () {
    // Gegenstück zu den Auslösern in Migration 0129 und 0131: Dort stehen
    // genau diese Werte in `jsonb_build_object('art', …)` — `spiel` für die
    // Live-Meldungen.
    expect(PushZiel.arten, {'fantasy', 'tipprunde', 'nachrichten', 'spiel'});
  });

  test('eine Live-Meldung führt aufs Spiel', () {
    final ziel = PushZiel.ausDaten({
      'art': 'spiel',
      'id': 'sportmonks:19432112',
      'kategorie': 'live_tore',
    });
    expect(ziel, isNotNull);
    expect(ziel!.id, 'sportmonks:19432112');
  });
}
