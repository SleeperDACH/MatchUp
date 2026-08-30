import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/transfer_vorgaenge.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';

/// Zugang und Abgang gehören zusammen, wenn sie zusammen passiert sind.
RosterMove _m(int id, String mgr, String pid, bool zugang, DateTime t,
        {String? weg}) =>
    RosterMove(
      id: id,
      leagueId: 'l1',
      managerId: mgr,
      playerId: pid,
      zugang: zugang,
      weg: weg,
      passiertAm: t,
    );

void main() {
  final t1 = DateTime(2026, 8, 30, 12, 0, 0, 0, 500);
  final t2 = DateTime(2026, 8, 30, 13, 0);

  test('Zugang und Abgang im selben Augenblick sind ein Vorgang', () {
    // Beide Zeilen entstehen in derselben Transaktion; Postgres' now() ist die
    // Transaktionszeit, die Werte sind exakt gleich.
    final v = vorgaengeAus([
      _m(2, 'a', 'rein', true, t1, weg: 'fa'),
      _m(1, 'a', 'raus', false, t1),
    ]);
    expect(v.length, 1);
    expect(v.single.rein.single.playerId, 'rein');
    expect(v.single.raus.single.playerId, 'raus');
    expect(v.single.bezeichnung, 'Verpflichtet');
    expect(v.single.nurAbgang, isFalse);
  });

  test('ein Trade bleibt je Manager getrennt', () {
    // „Eric bekommt Guirassy und gibt Amiri" und „Majusch bekommt Amiri und
    // gibt Guirassy" sind zwei Auskuenfte, nicht eine.
    final v = vorgaengeAus([
      _m(4, 'eric', 'guirassy', true, t1, weg: 'trade'),
      _m(3, 'eric', 'amiri', false, t1, weg: 'trade'),
      _m(2, 'majusch', 'amiri', true, t1, weg: 'trade'),
      _m(1, 'majusch', 'guirassy', false, t1, weg: 'trade'),
    ]);
    expect(v.length, 2);
    for (final vorgang in v) {
      expect(vorgang.rein.length, 1);
      expect(vorgang.raus.length, 1);
      expect(vorgang.weg, 'trade');
    }
  });

  test('zwei Vorgaenge derselben Minute fallen nicht zusammen', () {
    // Der Schluessel traegt die Zeit auf die Mikrosekunde genau. Wer rundet,
    // klebt zwei unabhaengige Vorgaenge aneinander.
    final gleich = DateTime(2026, 8, 30, 12, 0, 30);
    final v = vorgaengeAus([
      _m(2, 'a', 'x', true, gleich, weg: 'fa'),
      _m(1, 'a', 'y', true, gleich.add(const Duration(microseconds: 1)),
          weg: 'fa'),
    ]);
    expect(v.length, 2);
  });

  test('ein reiner Drop ist ein Vorgang ohne Zugang', () {
    final v = vorgaengeAus([_m(1, 'a', 'weg', false, t2)]);
    expect(v.single.nurAbgang, isTrue);
    expect(v.single.bezeichnung, 'Abgegeben');
  });

  test('juengste zuerst', () {
    final v = vorgaengeAus([
      _m(1, 'a', 'alt', true, t1, weg: 'fa'),
      _m(2, 'b', 'neu', true, t2, weg: 'fa'),
    ]);
    expect(v.first.rein.single.playerId, 'neu');
  });

  group('Marktlage eines abgegebenen Spielers', () {
    test('auf dem Waiver', () {
      expect(
          marktlage('x', aufWaiver: {'x'}, imKader: const {}),
          Marktlage.aufDemWaiver);
    });
    test('wieder frei', () {
      expect(marktlage('x', aufWaiver: const {}, imKader: const {}),
          Marktlage.frei);
    });
    test('schon vergeben schlaegt den Waiver', () {
      // Wer schon wieder in einem Kader steht, ist nicht holbar — auch wenn
      // sein Wire-Eintrag noch nicht aufgeraeumt ist.
      expect(marktlage('x', aufWaiver: {'x'}, imKader: {'x'}),
          Marktlage.vergeben);
    });
  });
}
