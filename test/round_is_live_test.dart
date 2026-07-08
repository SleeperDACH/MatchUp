import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/fantasy/providers.dart';

Fixture _fx(DateTime kickoff, FixtureStatus status) => Fixture(
      id: 'openligadb:${kickoff.millisecondsSinceEpoch}',
      leagueId: 'bundesliga',
      season: 2026,
      round: 1,
      roundName: '1. Spieltag',
      kickoff: kickoff,
      home: const TeamRef(id: 'a', name: 'A', shortName: 'A'),
      away: const TeamRef(id: 'b', name: 'B', shortName: 'B'),
      status: status,
    );

void main() {
  // Spieltag mit Anstoß Sa 15:30 und So 17:30.
  final sat = DateTime(2026, 8, 29, 15, 30);
  final sun = DateTime(2026, 8, 30, 17, 30);

  test('vor dem ersten Anpfiff → nicht live', () {
    final fx = [
      _fx(sat, FixtureStatus.scheduled),
      _fx(sun, FixtureStatus.scheduled),
    ];
    expect(roundIsLive(fx, sat.subtract(const Duration(minutes: 1))), isFalse);
  });

  test('erste Partie läuft → live', () {
    final fx = [
      _fx(sat, FixtureStatus.live),
      _fx(sun, FixtureStatus.scheduled),
    ];
    expect(roundIsLive(fx, sat.add(const Duration(minutes: 20))), isTrue);
  });

  test('Pause zwischen den Spielen (erstes beendet, zweites noch offen) → live', () {
    final fx = [
      _fx(sat, FixtureStatus.finished),
      _fx(sun, FixtureStatus.scheduled),
    ];
    expect(roundIsLive(fx, sat.add(const Duration(hours: 3))), isTrue);
  });

  test('alle Partien beendet → nicht live (Ergebnis steht)', () {
    final fx = [
      _fx(sat, FixtureStatus.finished),
      _fx(sun, FixtureStatus.finished),
    ];
    expect(roundIsLive(fx, sun.add(const Duration(hours: 2))), isFalse);
  });

  test('ohne Fixtures → nicht live', () {
    expect(roundIsLive(const [], DateTime(2026, 8, 29)), isFalse);
  });
}
