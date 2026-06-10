import '../../../core/models/models.dart';
import '../models/tip.dart';
import '../models/tip_round.dart';
import 'tip_scoring.dart';

/// Gesamtpunkte je Mitglied über alle beendeten Spiele — Grundlage für
/// die Sortierung der Tipp-Tabelle. Pure Funktion, damit sie testbar
/// ist und identisch zur Einzelspiel-Wertung ([scoreTip]) bleibt.
Map<String, int> totalPointsByMember({
  required List<RoundMember> members,
  required List<MemberTip> tips,
  required List<Fixture> fixtures,
  required ScoringRules rules,
}) {
  final results = {
    for (final f in fixtures)
      if (f.hasResult) f.id: f,
  };
  final totals = {for (final m in members) m.userId: 0};
  for (final tip in tips) {
    final fixture = results[tip.fixtureId];
    if (fixture == null || !totals.containsKey(tip.userId)) continue;
    totals[tip.userId] = totals[tip.userId]! +
        scoreTip(
          tipHome: tip.homeGoals,
          tipAway: tip.awayGoals,
          resultHome: fixture.homeScore!,
          resultAway: fixture.awayScore!,
          rules: rules,
        );
  }
  return totals;
}
