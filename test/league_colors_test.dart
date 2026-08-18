import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/league_colors.dart';

void main() {
  test('Die beiden Paletten überschneiden sich nicht', () {
    expect(kRedraftPalette.toSet().intersection(kDynastyPalette.toSet()),
        isEmpty);
  });

  test('Eine Liga behält ihre Farbe', () {
    final a = leagueColor('liga-42', FantasyMode.liga);
    final b = leagueColor('liga-42', FantasyMode.liga);
    expect(a, b);
  });

  test('Jeder Modus bleibt in seiner Familie', () {
    for (final id in ['a', 'b', 'c', 'liga-1', 'xyz', '9f8e7d', 'test']) {
      expect(kRedraftPalette, contains(leagueColor(id, FantasyMode.liga)));
      expect(kDynastyPalette, contains(leagueColor(id, FantasyMode.dynasty)));
    }
  });

  test('Beide Paletten werden auch wirklich ausgeschöpft', () {
    final ids = [for (var i = 0; i < 60; i++) 'liga-$i'];
    expect(ids.map((i) => leagueColor(i, FantasyMode.liga)).toSet().length,
        greaterThan(3));
    expect(ids.map((i) => leagueColor(i, FantasyMode.dynasty)).toSet().length,
        greaterThan(3));
  });
}
