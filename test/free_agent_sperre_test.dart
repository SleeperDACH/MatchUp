import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/aufstellung_sperre.dart';
import 'package:matchup/features/fantasy/logic/aufstellungs_prognose.dart';

/// Freie Spieler, deren Spiel schon läuft, dürfen nicht holbar sein.
///
/// Gemeldet als „der Waiver funktioniert nicht": Man konnte einen Spieler
/// aufnehmen und einen anderen abgeben, und es passierte nichts — der Zugang
/// kam nie in die Elf, weil die Aufstellung für ihn längst gesperrt war.
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
  const mainz = '1. FSV Mainz 05';
  const augsburg = 'FC Augsburg';
  const schalke = 'FC Schalke 04';

  // Spieltag 1: Mainz spielte am Samstag, Augsburg spielt Sonntag 15:30.
  final spiele = [
    _f(1, mainz, 'Paderborn', FixtureStatus.finished,
        DateTime.utc(2026, 8, 29, 13, 30)),
    _f(1, augsburg, schalke, FixtureStatus.scheduled,
        DateTime.utc(2026, 8, 30, 15, 30)),
    _f(2, schalke, mainz, FixtureStatus.scheduled,
        DateTime.utc(2026, 9, 5, 13, 30)),
  ];

  final sonntagFrueh = DateTime.utc(2026, 8, 30, 7, 0);

  test('die zaehlende Runde ist die noch nicht abgepfiffene', () {
    expect(aktiveRunde(spiele), 1);
  });

  test('Mainz hat gespielt -> gesperrt', () {
    final anpfiff = anpfiffJeVerein(spiele, aktiveRunde(spiele)!);
    expect(vereinSpieltGerade(mainz, anpfiff, sonntagFrueh), isTrue);
  });

  test('Augsburg spielt erst um 15:30 -> noch frei', () {
    final anpfiff = anpfiffJeVerein(spiele, aktiveRunde(spiele)!);
    expect(vereinSpieltGerade(augsburg, anpfiff, sonntagFrueh), isFalse);
  });

  test('nach dem Anpfiff ist auch Augsburg gesperrt', () {
    final anpfiff = anpfiffJeVerein(spiele, aktiveRunde(spiele)!);
    expect(
        vereinSpieltGerade(
            augsburg, anpfiff, DateTime.utc(2026, 8, 30, 15, 31)),
        isTrue);
  });

  test('ist der Spieltag durch, zaehlt die naechste Runde und alle sind frei',
      () {
    // **Der Punkt, an dem sich die Sperre von selbst loest.** Nach dem letzten
    // Abpfiff ist die zaehlende Runde die naechste, und deren Anpfiff liegt in
    // der Zukunft — ohne dass irgendwo etwas zurueckgesetzt werden muesste.
    final durch = [
      for (final f in spiele)
        if (f.round == 1)
          _f(f.round, f.home.name, f.away.name, FixtureStatus.finished,
              f.kickoff)
        else
          f
    ];
    final runde = aktiveRunde(durch);
    expect(runde, 2);
    final anpfiff = anpfiffJeVerein(durch, runde!);
    expect(vereinSpieltGerade(mainz, anpfiff, DateTime.utc(2026, 8, 31)),
        isFalse);
  });

  test('ein Verein ohne Ansetzung ist nicht gesperrt', () {
    // Ein Spieler aus einem Verein, der an dem Spieltag nicht spielt (oder gar
    // nicht mehr in der Liga ist). Ihn zu holen bringt niemandem einen
    // Vorteil — er punktet in dieser Runde ohnehin nicht.
    final anpfiff = anpfiffJeVerein(spiele, aktiveRunde(spiele)!);
    expect(vereinSpieltGerade('AS Monaco', anpfiff, sonntagFrueh), isFalse);
  });
}
