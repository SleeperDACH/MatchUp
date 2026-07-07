import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/fantasy/providers.dart';

Fixture _fx(int round, DateTime kickoff) => Fixture(
      id: 'openligadb:$round-${kickoff.millisecondsSinceEpoch}',
      leagueId: 'bundesliga',
      season: 2026,
      round: round,
      roundName: '$round. Spieltag',
      kickoff: kickoff,
      home: const TeamRef(id: 'a', name: 'A', shortName: 'A'),
      away: const TeamRef(id: 'b', name: 'B', shortName: 'B'),
      status: FixtureStatus.scheduled,
    );

void main() {
  // Spieltag 1: Anstöße Fr 20:30 + Sa 15:30; Spieltag 2 eine Woche später.
  final r1a = DateTime(2026, 8, 28, 20, 30);
  final r1b = DateTime(2026, 8, 29, 15, 30); // letzter Anpfiff ST 1
  final r2a = DateTime(2026, 9, 4, 20, 30);
  final r2b = DateTime(2026, 9, 5, 15, 30); // letzter Anpfiff ST 2
  final fixtures = [_fx(1, r1a), _fx(1, r1b), _fx(2, r2a), _fx(2, r2b)];

  test('vor Saisonstart → Spieltag 1', () {
    expect(currentFantasyRound(fixtures, DateTime(2026, 7, 7)), 1);
  });

  test('während Spieltag 1 → Spieltag 1', () {
    expect(currentFantasyRound(fixtures, DateTime(2026, 8, 29, 16, 0)), 1);
  });

  test('kurz vor 24h nach letztem Anpfiff ST1 → noch Spieltag 1', () {
    expect(currentFantasyRound(fixtures, r1b.add(const Duration(hours: 23))), 1);
  });

  test('genau 24h nach letztem Anpfiff ST1 → Spieltag 2', () {
    expect(currentFantasyRound(fixtures, r1b.add(const Duration(hours: 24))), 2);
  });

  test('nach Saisonende → letzter Spieltag', () {
    expect(currentFantasyRound(fixtures, DateTime(2026, 12, 1)), 2);
  });

  test('ohne Fixtures → Spieltag 1', () {
    expect(currentFantasyRound(const [], DateTime(2026, 8, 29)), 1);
  });
}
