import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/aufstellung_sperre.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/core/logic/vereins_kuerzel.dart';

/// Die Aufstellung sperrt **je Spieler**, zum Anpfiff seines Vereins — nicht
/// pauschal zum Beginn des Spieltags. Maßgeblich ist `fantasy_set_lineup`
/// (Migration 0084); diese Regel muss dasselbe meinen, sonst zeigt die App ein
/// Feld als bedienbar, das der Server dann ablehnt.
Fixture _spiel(String heim, String aus, DateTime kickoff, {int runde = 1}) =>
    Fixture(
      id: 'sportmonks:${heim.hashCode}',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: 'Spieltag $runde',
      kickoff: kickoff,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: aus, name: aus, shortName: aus),
      status: FixtureStatus.scheduled,
    );

FantasyPlayer _spieler(String verein) => FantasyPlayer(
      id: 'p-$verein',
      name: 'Spieler $verein',
      position: PlayerPosition.mid,
      club: verein,
      birthDate: DateTime(2000),
      nationality: 'DE',
    );

void main() {
  final freitag = DateTime(2026, 8, 28, 20, 30);
  final samstag = DateTime(2026, 8, 29, 15, 30);
  final spiele = [
    _spiel('FC Bayern München', 'VfB Stuttgart', freitag),
    _spiel('RB Leipzig', '1. FC Köln', samstag),
    // Ein Spiel aus einer anderen Runde darf nicht hineinreden.
    _spiel('FC Bayern München', 'RB Leipzig', DateTime(2026, 9, 5), runde: 2),
  ];

  group('Sperre je Spieler', () {
    test('Anpfiff wird je Verein aufgelöst, nur für die gefragte Runde', () {
      // **Die Karte ist kanonisch geschlüsselt**, seit der Spielplan von
      // Sportmonks kommt: Der Kader trägt „1. FC Köln", der Spielplan
      // „FC Köln". Gesucht wird deshalb über `vereinKanonisch` — dieselbe
      // Form, die `spielerGesperrt` beim Nachschlagen benutzt.
      final a = anpfiffJeVerein(spiele, 1);
      expect(a[vereinKanonisch('FC Bayern München')], freitag);
      expect(a[vereinKanonisch('VfB Stuttgart')], freitag);
      expect(a[vereinKanonisch('RB Leipzig')], samstag);
      expect(a.containsKey(vereinKanonisch('Borussia Dortmund')), isFalse);
    });

    test('verschiedene Schreibweisen treffen denselben Verein', () {
      // **Der Fall, der den Server in Migration 0108 eine Woche gekostet
      // hat**, jetzt auf der Client-Seite: Sieben von achtzehn Vereinen
      // schreiben sich im Kader anders als im Sportmonks-Spielplan. Ohne
      // kanonischen Vergleich fände der Abgleich nichts — und „kein Spiel
      // gefunden" heißt „nicht gesperrt", die Elf ließe sich also mitten im
      // laufenden Spiel ändern.
      final a = anpfiffJeVerein([
        _spiel('FC Köln', 'Werder Bremen', freitag),
      ], 1);
      final koelner = FantasyPlayer(
        id: 'p1',
        name: 'Timo Hübers',
        position: PlayerPosition.def,
        club: '1. FC Köln', // Schreibweise des Kaders
        nationality: 'de',
        birthDate: DateTime(1996, 7, 20),
      );
      expect(spielerGesperrt(koelner, a, freitag.add(const Duration(hours: 1))),
          isTrue);
      expect(spielerGesperrt(koelner, a, freitag.subtract(const Duration(hours: 1))),
          isFalse);
    });

    test('nach dem Freitagsspiel ist nur der Freitagsspieler gesperrt', () {
      final a = anpfiffJeVerein(spiele, 1);
      final jetzt = freitag.add(const Duration(minutes: 5));
      expect(spielerGesperrt(_spieler('FC Bayern München'), a, jetzt), isTrue);
      // Genau das war vorher falsch: Der Samstagsspieler war mitgesperrt.
      expect(spielerGesperrt(_spieler('RB Leipzig'), a, jetzt), isFalse);
    });

    test('exakt zum Anpfiff ist zu, eine Minute davor offen', () {
      final a = anpfiffJeVerein(spiele, 1);
      final p = _spieler('FC Bayern München');
      expect(spielerGesperrt(p, a, freitag), isTrue);
      expect(
        spielerGesperrt(p, a, freitag.subtract(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('ohne Spiel keine Sperre', () {
      // Abgewanderte Spieler stehen noch im Pool, wenn sie gerostert sind —
      // gemessen: „AS Monaco". Sie punkten in dieser Runde ohnehin nicht.
      final a = anpfiffJeVerein(spiele, 1);
      expect(spielerGesperrt(_spieler('AS Monaco'), a, samstag), isFalse);
    });

    test('nochFrei zählt nur die beweglichen', () {
      final a = anpfiffJeVerein(spiele, 1);
      final jetzt = freitag.add(const Duration(minutes: 5));
      final elf = [
        _spieler('FC Bayern München'),
        _spieler('VfB Stuttgart'),
        _spieler('RB Leipzig'),
      ];
      expect(nochFrei(elf, a, jetzt), 1);
    });

    test('bei Dubletten gewinnt der frühere Anpfiff', () {
      // Derselbe Spieltag kann doppelt gespiegelt sein (openligadb + sportmonks).
      final doppelt = [
        _spiel('SC Freiburg', 'FC Augsburg', samstag),
        _spiel('SC Freiburg', 'FC Augsburg', freitag),
      ];
      expect(anpfiffJeVerein(doppelt, 1)[vereinKanonisch('SC Freiburg')],
          freitag);
    });
  });
}
