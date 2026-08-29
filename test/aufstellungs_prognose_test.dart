import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/aufstellungs_prognose.dart';

/// Der Umschaltzeitpunkt der Aufstellungsprognose.
///
/// Jeder Fall hier ist eine Entscheidung, die man beim Bauen falsch treffen
/// kann — allen voran die naheliegende „nimm das nächste Spiel des Vereins".
Fixture _f(int runde, String heim, String gast, FixtureStatus st, DateTime k) =>
    Fixture(
      id: 'sportmonks:$runde-$heim',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: 'Spieltag $runde',
      kickoff: k,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: gast, name: gast, shortName: gast),
      status: st,
    );

void main() {
  const bvb = 'Borussia Dortmund';
  const hsv = 'Hamburger SV';
  const fcb = 'FC Bayern München';
  const s04 = 'Schalke 04';

  // Spieltag 1: BVB spielt Freitag, das letzte Spiel steigt Sonntag.
  List<Fixture> saison({
    required FixtureStatus bvbSpiel1,
    required FixtureStatus letztesSpiel1,
  }) =>
      [
        _f(1, bvb, hsv, bvbSpiel1, DateTime(2026, 8, 28, 20, 30)),
        _f(1, fcb, s04, letztesSpiel1, DateTime(2026, 8, 30, 17, 30)),
        _f(2, s04, bvb, FixtureStatus.scheduled, DateTime(2026, 9, 5, 15, 30)),
        _f(2, hsv, fcb, FixtureStatus.scheduled, DateTime(2026, 9, 5, 15, 30)),
      ];

  test('vor dem Spieltag: das eigene Spiel dieses Spieltags', () {
    final s = saison(
        bvbSpiel1: FixtureStatus.scheduled,
        letztesSpiel1: FixtureStatus.scheduled);
    expect(spielFuerPrognose(s, bvb)?.round, 1);
  });

  test('eigenes Spiel gelaufen, Spieltag laeuft noch: bleibt bei Spieltag 1',
      () {
    // **Der Kern der Regel.** „Naechstes Spiel des Vereins" wuerde hier schon
    // auf Spieltag 2 zeigen — fuer den es noch gar keine Prognose gibt, und
    // waehrend der Spieltag noch laeuft.
    final s = saison(
        bvbSpiel1: FixtureStatus.finished,
        letztesSpiel1: FixtureStatus.scheduled);
    expect(spielFuerPrognose(s, bvb)?.round, 1);
  });

  test('nach dem Abpfiff des letzten Spiels: Spieltag 2', () {
    final s = saison(
        bvbSpiel1: FixtureStatus.finished,
        letztesSpiel1: FixtureStatus.finished);
    expect(spielFuerPrognose(s, bvb)?.round, 2);
  });

  test('ein laufendes Spiel haelt den Spieltag offen', () {
    final s = saison(
        bvbSpiel1: FixtureStatus.finished, letztesSpiel1: FixtureStatus.live);
    expect(aktiveRunde(s), 1);
  });

  test('spielfrei in der aktiven Runde: das naechste eigene Spiel', () {
    // Der Verein hat in Runde 1 keine Ansetzung. Ohne Rueckfall staende das
    // Profil ohne Auskunft da, obwohl es eine gibt.
    final s = [
      _f(1, fcb, s04, FixtureStatus.scheduled, DateTime(2026, 8, 30, 17, 30)),
      _f(2, s04, bvb, FixtureStatus.scheduled, DateTime(2026, 9, 5, 15, 30)),
    ];
    expect(spielFuerPrognose(s, bvb)?.round, 2);
  });

  test('Saison durch: kein Spiel', () {
    final s = [
      _f(1, bvb, hsv, FixtureStatus.finished, DateTime(2026, 8, 28, 20, 30)),
    ];
    expect(spielFuerPrognose(s, bvb), isNull);
  });

  test('letztes gespieltes Spiel ist das juengste beendete', () {
    final s = [
      _f(1, bvb, hsv, FixtureStatus.finished, DateTime(2026, 8, 28, 20, 30)),
      _f(2, s04, bvb, FixtureStatus.finished, DateTime(2026, 9, 5, 15, 30)),
      _f(3, bvb, fcb, FixtureStatus.scheduled, DateTime(2026, 9, 12, 15, 30)),
    ];
    expect(letztesGespieltes(s, bvb)?.round, 2);
  });
}
