import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/league_colors.dart';

void main() {
  test('Redraft ist grün, Dynasty rot', () {
    expect(leagueColor(FantasyMode.liga), MatchUpColors.green);
    expect(leagueColor(FantasyMode.dynasty), MatchUpColors.red);
  });

  test('die beiden Modi teilen sich keine Farbe', () {
    expect(leagueColor(FantasyMode.liga),
        isNot(leagueColor(FantasyMode.dynasty)));
  });
}
