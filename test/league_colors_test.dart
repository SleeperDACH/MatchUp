import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/league_colors.dart';

/// **Eine Liga trägt das Markengrün.**
///
/// Vorher standen hier zwei Fälle: „Redraft grün, Dynasty rot" und „die beiden
/// Modi teilen sich keine Farbe". Der zweite ist mit dem Wegfall von Dynasty
/// (27.09.2026) keine Aussage mehr — ohne zweiten Modus gibt es nichts zu
/// unterscheiden, und ein Test, der das behauptet, prüft nur noch sich selbst.
void main() {
  test('eine Liga ist grün', () {
    expect(leagueColor(FantasyMode.liga), MatchUpColors.green);
  });
}
