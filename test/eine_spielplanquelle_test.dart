import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/logic/vereins_kuerzel.dart';
import 'package:matchup/core/models/models.dart';

/// **Eine Quelle für den Spielplan, nicht zwei.**
///
/// Gemeldet: *„Wenn ich innerhalb einer Fantasy-Liga auf ein Spiel gehe, wird
/// mir keine Aufstellung angezeigt, keine Spieldetails, keine Tabelle,
/// nichts."*
///
/// Die Ursache war eine zweite Quelle: `fantasySeasonFixturesProvider` holte
/// den Spielplan fest bei OpenLigaDB, während Live-Tab, Vereinsseite und der
/// Server Sportmonks lesen. Die Fixture-IDs hießen damit `openligadb:…`, und
/// `matchDetailProvider` leitet den Adapter aus dem Präfix ab — für OpenLigaDB
/// gibt es weder Aufstellung noch Spielverlauf. Der Tipp führte auf eine leere
/// Seite.
///
/// Derselbe Riss hatte schon einmal Geld gekostet: „man kann ihn aufnehmen, es
/// passiert überhaupt nichts" (Migration 0107) entstand daraus, dass der
/// Client OpenLigaDB las und der Server `sportmonks:`-Zeilen rechnete.
void main() {
  test('die Fantasy-Fixtures kommen nicht mehr fest von OpenLigaDB', () {
    // **Ein Wächter über der Quelle, kein Netzaufruf.** Welcher Adapter
    // gewählt wird, entscheidet `sportsProviderFor(league)` anhand von
    // `LeagueInfo.providerId` — genau wie beim Live-Tab. Ein fest verdrahtetes
    // `OpenLigaDbProvider()` an dieser Stelle wäre die Rückkehr zum Riss.
    final quelle =
        File('lib/features/fantasy/providers.dart').readAsStringSync();
    final start = quelle.indexOf('final fantasySeasonFixturesProvider');
    expect(start, greaterThan(-1), reason: 'Provider umbenannt?');
    final ende = quelle.indexOf('});', start);
    final rumpf = quelle.substring(start, ende);

    expect(rumpf.contains('OpenLigaDbProvider('), isFalse,
        reason: 'Der Fantasy-Spielplan muss dieselbe Quelle lesen wie der '
            'Live-Tab, sonst zeigen die Fixture-IDs ins Leere.');
    expect(rumpf.contains('sportsProviderFor'), isTrue);
  });

  test('die Bundesliga liefert Sportmonks-IDs', () {
    // Steht der Wettbewerb je wieder auf OpenLigaDB, ist die Ableitung oben
    // hinfällig — dann muss auch `matchDetailProvider` neu bedacht werden.
    expect(Leagues.bundesliga.providerId, 'sportmonks');
  });

  test('Kader und Spielplan schreiben Vereine verschieden', () {
    // **Der Preis der Umstellung, und warum jeder Abgleich kanonisch läuft.**
    // Links die Schreibweise aus `players.club` (OpenLigaDB), rechts die des
    // Sportmonks-Spielplans. Buchstabengetreu verglichen fände der Abgleich
    // für sieben von achtzehn Vereinen nichts — und „kein Spiel gefunden"
    // heißt in der Aufstellungssperre „nicht gesperrt".
    const paare = {
      '1. FC Köln': 'FC Köln',
      '1. FSV Mainz 05': 'FSV Mainz 05',
      'SV Werder Bremen': 'Werder Bremen',
      'SV 07 Elversberg': 'Elversberg',
      'SC Paderborn 07': 'Paderborn',
      'FC Schalke 04': 'Schalke 04',
      '1. FC Union Berlin': 'FC Union Berlin',
    };
    paare.forEach((kader, spielplan) {
      expect(kader, isNot(spielplan), reason: 'sonst wäre der Test sinnlos');
      expect(vereinKanonisch(kader), vereinKanonisch(spielplan),
          reason: '$kader und $spielplan müssen als derselbe Verein gelten');
    });
  });

  test('verschiedene Vereine fallen nicht auf dieselbe Form', () {
    // Die Gegenprobe: Ein zu grober Vergleich wäre schlimmer als ein zu
    // strenger — er würde zwei Vereine verwechseln.
    const vereine = [
      'FC Bayern München',
      'Borussia Dortmund',
      'Borussia Mönchengladbach',
      'RB Leipzig',
      'Bayer 04 Leverkusen',
      '1. FC Köln',
      '1. FC Union Berlin',
      'Hertha BSC',
      'Hamburger SV',
      'FC St. Pauli',
      '1. FSV Mainz 05',
      'FC Augsburg',
      'SC Freiburg',
      'VfB Stuttgart',
      'VfL Wolfsburg',
      'SV Werder Bremen',
      'TSG Hoffenheim',
      'Eintracht Frankfurt',
    ];
    final formen = vereine.map(vereinKanonisch).toSet();
    expect(formen.length, vereine.length,
        reason: 'jeder Verein braucht eine eigene kanonische Form');
  });
}
