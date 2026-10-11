import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/laufende_runde.dart';

/// Gemeldet: „Im Spielerprofil wird die Punktzahl des aktuellen Spiels erst
/// nach dem Spieltag angezeigt." Sie steht jetzt **ab Abpfiff seines Spiels**.

Fixture _f(String heim, String aus, FixtureStatus stand) => Fixture(
      id: 'sportmonks:$heim-$aus',
      leagueId: 'bundesliga',
      season: 2026,
      round: 5,
      roundName: 'Spieltag 5',
      kickoff: DateTime(2026, 10, 10, 15, 30),
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: aus, name: aus, shortName: aus),
      status: stand,
    );

const _tor = PlayerMatchStats(minutes: 90, goals: 1);
final _alt = <int, Map<String, PlayerMatchStats>>{
  4: {'p1': const PlayerMatchStats(minutes: 90)},
};

void main() {
  test('sein Spiel ist abgepfiffen: die Runde steht da, aus den frischen Daten',
      () {
    final r = mitLaufenderRunde(
      saison: _alt,
      runde: 5,
      spielerId: 'p1',
      // Kader schreibt die OpenLigaDB-Form, der Spielplan die von Sportmonks.
      verein: '1. FC Köln',
      spiele: [
        _f('FC Köln', 'Hamburger SV', FixtureStatus.finished),
        _f('FC Bayern München', 'VfB Stuttgart', FixtureStatus.scheduled),
      ],
      live: {'p1': _tor},
    );
    expect(r[5]?['p1']?.goals, 1);
    expect(r[4], isNotNull, reason: 'frühere Runden bleiben unberührt');
  });

  test('sein Spiel läuft noch: die Runde fällt heraus, auch mit Zwischenstand',
      () {
    final r = mitLaufenderRunde(
      saison: {
        ..._alt,
        5: {'p1': const PlayerMatchStats(minutes: 30)},
      },
      runde: 5,
      spielerId: 'p1',
      verein: '1. FC Köln',
      spiele: [_f('FC Köln', 'Hamburger SV', FixtureStatus.live)],
      live: {'p1': _tor},
    );
    expect(r.containsKey(5), isFalse);
  });

  test('abgepfiffen, aber nicht gespielt: gewertet, ohne Eintrag', () {
    final r = mitLaufenderRunde(
      saison: _alt,
      runde: 5,
      spielerId: 'p1',
      verein: '1. FC Köln',
      spiele: [_f('FC Köln', 'Hamburger SV', FixtureStatus.finished)],
      live: const {},
    );
    expect(r.containsKey(5), isTrue);
    expect(r[5], isEmpty);
  });

  test('Verein spielfrei: erst wenn der ganze Spieltag durch ist', () {
    Map<int, Map<String, PlayerMatchStats>> mit(FixtureStatus stand) =>
        mitLaufenderRunde(
          saison: _alt,
          runde: 5,
          spielerId: 'p1',
          verein: '1. FC Köln',
          spiele: [_f('FC Bayern München', 'VfB Stuttgart', stand)],
          live: const {},
        );
    expect(mit(FixtureStatus.live).containsKey(5), isFalse);
    expect(mit(FixtureStatus.finished).containsKey(5), isTrue);
  });
}
