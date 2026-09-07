import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/naechstes_spiel.dart';

/// **Der Spielplan im Spielerprofil fand sieben Vereine nicht.**
///
/// Gemeldet: *„Warum liegt für Schalke 04 kein Spielplan vor? Vorhin hatte ich
/// das auch bei Köln."* — und der entscheidende Hinweis kam nach: *„Im Live-Tab
/// sind die Spielpläne von Köln und Schalke ja da. Die fehlen nur im
/// Spielerprofil."*
///
/// Damit war es kein Datenproblem, sondern ein Vergleich: Der Reiter prüfte
/// `f.home.name == club`, buchstabengenau. `players.club` trägt die
/// OpenLigaDB-Schreibweise, der Spielplan die von Sportmonks — und bei sieben
/// von achtzehn Bundesligavereinen gehen sie auseinander. Der Live-Tab liest
/// beide Seiten aus derselben Quelle und musste nie abgleichen; deshalb war
/// dort alles in Ordnung.
///
/// Dieselbe Reparatur wie in Migration 0108 und an fünf anderen Client-Stellen:
/// verglichen wird die kanonische Form.

/// Die sieben Paare, an denen es scheiterte — gemessen, nicht ausgedacht.
const _paare = <String, String>{
  '1. FC Köln': 'FC Köln',
  'FC Schalke 04': 'Schalke 04',
  '1. FSV Mainz 05': 'FSV Mainz 05',
  'SV Werder Bremen': 'Werder Bremen',
  '1. FC Union Berlin': 'FC Union Berlin',
  'SV 07 Elversberg': 'Elversberg',
  'SC Paderborn 07': 'Paderborn',
};

Fixture _f(String heim, String gast, int runde) => Fixture(
      id: 'sportmonks:$heim$runde',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: '$runde. Spieltag',
      kickoff: DateTime(2026, 9, runde + 4, 15, 30),
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: gast, name: gast, shortName: gast),
      status: FixtureStatus.scheduled,
    );

void main() {
  test('jede der sieben Schreibweisen findet ihren Spielplan', () {
    for (final paar in _paare.entries) {
      final kaderName = paar.key;
      final spielplanName = paar.value;
      final alle = [
        _f(spielplanName, 'FC Bayern München', 1),
        _f('Borussia Dortmund', spielplanName, 2),
        _f('RB Leipzig', 'FC Bayern München', 3),
      ];
      expect(
        spieleDesVereins(alle, kaderName).length,
        2,
        reason: '„$kaderName" muss „$spielplanName" im Spielplan finden',
      );
    }
  });

  test('gegengeprüft: buchstabengenau fände keinen einzigen', () {
    // Ohne die kanonische Form wäre die Liste für alle sieben leer — genau der
    // gemeldete Zustand.
    for (final paar in _paare.entries) {
      expect(paar.key == paar.value, isFalse);
    }
  });

  test('Vereine mit gleicher Schreibweise funktionieren weiter', () {
    final alle = [
      _f('Borussia Dortmund', 'Hamburger SV', 1),
      _f('RB Leipzig', 'Borussia Dortmund', 2),
    ];
    expect(spieleDesVereins(alle, 'Borussia Dortmund').length, 2);
    expect(spieleDesVereins(alle, 'Hamburger SV').length, 1);
  });

  test('ein fremder Verein bekommt nichts', () {
    // Ein zu grober Vergleich wäre schlimmer als ein zu strenger: Er
    // verwechselte zwei Vereine.
    final alle = [_f('FC Köln', 'FC Bayern München', 1)];
    expect(spieleDesVereins(alle, 'SC Freiburg'), isEmpty);
  });

  test('nach Anstoß sortiert, die Eingabe bleibt unangetastet', () {
    final alle = [
      _f('Schalke 04', 'FC Bayern München', 3),
      _f('FC Bayern München', 'Schalke 04', 1),
    ];
    final kopie = [...alle];
    final seine = spieleDesVereins(alle, 'FC Schalke 04');
    expect(seine.map((f) => f.round), [1, 3]);
    expect(alle.map((f) => f.round), kopie.map((f) => f.round));
  });
}
