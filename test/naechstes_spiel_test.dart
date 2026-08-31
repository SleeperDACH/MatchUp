import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/logic/vereins_kuerzel.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/naechstes_spiel.dart';

/// **Vor dem Anpfiff steht das Spiel in der Punktebox, nicht ein Strich.**
///
/// Gemeldet: „Diesen Spieltag war es so, dass bereits zum Start des Spieltages
/// schon 0,0 Punkte angezeigt wurden." Die Ursache: Ob Punkte oder ein Strich
/// erschienen, hing daran, ob eine **Statistikzeile** existierte — und die war
/// vor dem Anstoß schon da. Maßgeblich ist jetzt der Anpfiff.
Fixture _f(int runde, String heim, String aus, DateTime anpfiff) => Fixture(
      id: 'sportmonks:$heim$runde',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: 'Spieltag $runde',
      kickoff: anpfiff,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: aus, name: aus, shortName: aus),
      status: FixtureStatus.scheduled,
    );

void main() {
  final spiele = [
    _f(2, 'FC Bayern München', 'Borussia Dortmund', DateTime(2026, 9, 4, 20, 30)),
    _f(2, 'SV Werder Bremen', '1. FSV Mainz 05', DateTime(2026, 9, 5, 15, 30)),
    _f(3, 'Borussia Dortmund', 'SV Werder Bremen', DateTime(2026, 9, 12, 20, 30)),
  ];

  group('naechstesSpiel', () {
    test('findet den Gegner zu Hause und auswärts', () {
      final heim = naechstesSpiel(spiele, 2, 'FC Bayern München')!;
      expect(heim.gegner, 'Borussia Dortmund');
      expect(heim.heim, isTrue);

      final aus = naechstesSpiel(spiele, 2, 'Borussia Dortmund')!;
      expect(aus.gegner, 'FC Bayern München');
      expect(aus.heim, isFalse);
    });

    test('nur die gefragte Runde zählt', () {
      expect(naechstesSpiel(spiele, 3, 'FC Bayern München'), isNull,
          reason: 'An Spieltag 3 sind sie nicht angesetzt');
      expect(naechstesSpiel(spiele, 3, 'SV Werder Bremen')!.gegner,
          'Borussia Dortmund');
    });

    test('ein Verein ohne Ansetzung liefert null', () {
      // Kein Fehler: Kader enthalten Spieler von Vereinen, die frei haben
      // oder gar nicht in der Liga spielen.
      expect(naechstesSpiel(spiele, 2, 'AS Monaco'), isNull);
    });
  });

  test('anpfiffKurz schreibt Wochentag und Uhrzeit', () {
    expect(anpfiffKurz(DateTime(2026, 9, 5, 15, 30)), 'Sa 15:30');
    expect(anpfiffKurz(DateTime(2026, 9, 4, 20, 30)), 'Fr 20:30');
    expect(anpfiffKurz(DateTime(2026, 9, 6, 9, 5)), 'So 09:05');
  });

  group('vereinsKuerzel', () {
    test('die geläufigen Kürzel stehen fest', () {
      // Abgeleitet käme aus „FC Bayern München" ein „FB" heraus, aus
      // „Borussia Mönchengladbach" ein „BM". Beides erkennt niemand.
      expect(vereinsKuerzel('FC Bayern München'), 'FCB');
      expect(vereinsKuerzel('Borussia Dortmund'), 'BVB');
      expect(vereinsKuerzel('FC Schalke 04'), 'S04');
      expect(vereinsKuerzel('Bayer 04 Leverkusen'), 'B04');
      expect(vereinsKuerzel('Borussia Mönchengladbach'), 'BMG');
    });

    test('beide Schreibweisen derselben Quelle treffen denselben Eintrag', () {
      // Die Kader schreiben „1. FSV Mainz 05", der Sportmonks-Spielplan
      // „FSV Mainz 05" — dass die beiden auseinanderliefen, hat an anderer
      // Stelle schon einmal eine Woche gekostet.
      expect(vereinsKuerzel('1. FSV Mainz 05'), 'M05');
      expect(vereinsKuerzel('FSV Mainz 05'), 'M05');
      expect(vereinsKuerzel('SV 07 Elversberg'), 'SVE');
      expect(vereinsKuerzel('Elversberg'), 'SVE');
      expect(vereinsKuerzel('1. FC Köln'), 'KÖL');
      expect(vereinsKuerzel('FC Köln'), 'KÖL');
    });

    test('ein unbekannter Verein bekommt ein abgeleitetes Kürzel', () {
      // Das **längste** Wort, nicht das erste: „AS" erkennt niemand.
      expect(vereinsKuerzel('AS Monaco'), 'MON');
      expect(vereinsKuerzel('Real Madrid'), 'MAD');
    });
  });
}
