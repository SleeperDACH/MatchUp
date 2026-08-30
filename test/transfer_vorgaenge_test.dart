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

  _ereignisse();

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

/// Ein Trade gehört in **eine** Box — aber nur mit der richtigen Gegenseite.
void _ereignisse() {
  RosterMove m(int id, String mgr, String pid, bool zugang, DateTime t) =>
      RosterMove(
        id: id,
        leagueId: 'l1',
        managerId: mgr,
        playerId: pid,
        zugang: zugang,
        weg: 'trade',
        passiertAm: t,
      );

  group('Trades zu einem Ereignis', () {
    final t = DateTime(2026, 8, 30, 5, 47, 17, 294);

    test('beide Seiten eines Tauschs werden ein Ereignis', () {
      final e = ereignisseAus([
        m(4, 'eric', 'guirassy', true, t),
        m(3, 'eric', 'amiri', false, t),
        m(2, 'majusch', 'amiri', true, t),
        m(1, 'majusch', 'guirassy', false, t),
      ]);
      expect(e.length, 1);
      expect(e.single.istTrade, isTrue);
      expect(e.single.seiten.length, 2);
    });

    test('zwei gleichzeitige Trades werden NICHT verwechselt', () {
      // **Der Fall, an dem eine Gruppierung nach Zeit allein scheitert.**
      // fantasy_faellige_trades_ausfuehren arbeitet alle faelligen Trades in
      // einer Transaktion ab — sie tragen denselben Zeitstempel.
      final e = ereignisseAus([
        // Trade 1: eric <-> majusch
        m(8, 'eric', 'guirassy', true, t),
        m(7, 'eric', 'amiri', false, t),
        m(6, 'majusch', 'amiri', true, t),
        m(5, 'majusch', 'guirassy', false, t),
        // Trade 2: anna <-> bert, zur exakt gleichen Zeit
        m(4, 'anna', 'kane', true, t),
        m(3, 'anna', 'sane', false, t),
        m(2, 'bert', 'sane', true, t),
        m(1, 'bert', 'kane', false, t),
      ]);
      expect(e.length, 2, reason: 'zwei Trades, zwei Ereignisse');
      for (final x in e) {
        expect(x.seiten.length, 2);
        final namen = x.seiten.map((s) => s.managerId).toSet();
        // Kein Ereignis darf Manager aus verschiedenen Trades mischen.
        expect(
            namen.containsAll({'eric', 'majusch'}) ||
                namen.containsAll({'anna', 'bert'}),
            isTrue);
      }
    });

    test('derselbe Spieler zweimal getradet bleibt zwei Ereignisse', () {
      // **Der Fall aus der Praxis** (Nicolas Kristof, 28.08.2026): erst von
      // hollmann zu SFV03, gut eine halbe Stunde spaeter von SFV03 zu julius.
      // Die Rueckfuellung hatte beide Traden an die eine vorhandene
      // Kaderzeile gehaengt und damit den ersten Tausch auf die Zeit des
      // zweiten gelegt; der Zwischenbesitzer verschwand.
      final frueh = DateTime(2026, 8, 28, 17, 58, 47, 63);
      final spaet = DateTime(2026, 8, 28, 18, 34, 33, 863);
      final e = ereignisseAus([
        m(1, 'hollmann', 'kristof', false, frueh),
        m(2, 'sfv', 'kristof', true, frueh),
        m(3, 'sfv', 'zentner', false, frueh),
        m(4, 'hollmann', 'zentner', true, frueh),
        m(5, 'sfv', 'kristof', false, spaet),
        m(6, 'julius', 'kristof', true, spaet),
        m(7, 'julius', 'schwolow', false, spaet),
        m(8, 'sfv', 'schwolow', true, spaet),
      ]);
      expect(e.length, 2, reason: 'zwei Tausche, zwei Ereignisse');
      // Juengster zuerst: SFV03 gibt Kristof an julius.
      expect(e.first.passiertAm, spaet);
      expect(e.first.seiten.map((s) => s.managerId).toSet(),
          {'sfv', 'julius'});
      // Und der aeltere behaelt seinen eigenen Zeitpunkt samt Beteiligten.
      expect(e.last.passiertAm, frueh);
      expect(e.last.seiten.map((s) => s.managerId).toSet(),
          {'sfv', 'hollmann'});
    });

    test('eine Seite ohne Gegenstueck bleibt allein stehen', () {
      // Kommt vor, wenn die Gegenseite aus der Rueckfuellung nicht
      // rekonstruiert werden konnte — dann lieber halb als falsch.
      final e = ereignisseAus([
        m(2, 'eric', 'guirassy', true, t),
        m(1, 'eric', 'amiri', false, t),
      ]);
      expect(e.single.istTrade, isFalse);
      expect(e.single.seiten.single.managerId, 'eric');
    });

    test('Free Agency bleibt ein Ereignis je Manager', () {
      final e = ereignisseAus([
        RosterMove(
            id: 2,
            leagueId: 'l1',
            managerId: 'a',
            playerId: 'x',
            zugang: true,
            weg: 'fa',
            passiertAm: t),
        RosterMove(
            id: 1,
            leagueId: 'l1',
            managerId: 'b',
            playerId: 'y',
            zugang: true,
            weg: 'fa',
            passiertAm: t),
      ]);
      expect(e.length, 2);
      expect(e.every((x) => !x.istTrade), isTrue);
    });
  });
}
