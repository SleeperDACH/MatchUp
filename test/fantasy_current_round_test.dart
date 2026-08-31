import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/providers.dart';

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

/// **Der Spieltag wechselt an der Waiver-Frist**, also Montag 15:00.
///
/// Vorher galten 24 Stunden nach dem letzten Anpfiff — eine Zahl, die je
/// Spieltag woanders hinfiel: mal Montag 17:30, bei einem Sonntagabendspiel
/// erst 19:30. Jetzt derselbe Zeitpunkt, an dem auch die Waiver-Anträge
/// vergeben werden.
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

  test('Sonntagabend nach dem Abpfiff → noch Spieltag 1', () {
    // Der beendete Spieltag steht bis Montag 15:00; die Abrechnung soll man
    // in Ruhe ansehen können.
    expect(currentFantasyRound(fixtures, DateTime(2026, 8, 30, 22)), 1);
  });

  test('Montag 14:59 → noch Spieltag 1', () {
    expect(currentFantasyRound(fixtures, DateTime(2026, 8, 31, 14, 59)), 1);
  });

  test('Montag 15:00 → Spieltag 2', () {
    // Punktgenau zur Frist, nicht eine Sekunde später: Zu diesem Zeitpunkt
    // werden auch die Waiver-Anträge vergeben.
    expect(currentFantasyRound(fixtures, DateTime(2026, 8, 31, 15)), 2);
  });

  test('nach Saisonende → letzter Spieltag', () {
    expect(currentFantasyRound(fixtures, DateTime(2026, 12, 1)), 2);
  });

  test('ohne Fixtures → Spieltag 1', () {
    expect(currentFantasyRound(const [], DateTime(2026, 8, 29)), 1);
  });
}
