import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';

void main() {
  test('Länderspiele folgen dem Kalenderjahr, Ligen der Saison', () {
    expect(Leagues.deutschland.seasonFor(DateTime(2026, 11, 18)), 2026);
    expect(Leagues.deutschland.seasonFor(DateTime(2027, 1, 5)), 2027);
    expect(Leagues.deutschland.ohneLigasaison, isTrue);
    expect(Leagues.bundesliga.seasonFor(DateTime(2027, 1, 5)), 2026);
    expect(Leagues.bundesliga.ohneLigasaison, isFalse);
  });
}
