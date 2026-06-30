import '../../../core/data/odds/frozen_odds.dart';
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
  Map<String, FrozenOdds> frozenOdds = const {},
}) {
  // Live-Spiele zählen mit ihrem aktuellen Spielstand mit (vorläufige
  // Punkte, die sich je Tor ändern); endgültig wird's mit `finished`.
  // Bewusst client-seitig — die SQL-View `tip_round_standings` bleibt
  // die gesetzte Endabrechnung (nur `finished`). Die Wertungsformel
  // ([scoreTip]) ist in beiden identisch.
  final results = {
    for (final f in fixtures)
      if (f.hasScore) f.id: f,
  };
  final totals = {for (final m in members) m.userId: 0};
  for (final tip in tips) {
    final fixture = results[tip.fixtureId];
    if (fixture == null || !totals.containsKey(tip.userId)) continue;
    final base = scoreTip(
      tipHome: tip.homeGoals,
      tipAway: tip.awayGoals,
      resultHome: fixture.homeScore!,
      resultAway: fixture.awayScore!,
      rules: rules,
    );
    final fo = frozenOdds[tip.fixtureId];
    final bonus = oddsBonus(
      tipHome: tip.homeGoals,
      tipAway: tip.awayGoals,
      resultHome: fixture.homeScore!,
      resultAway: fixture.awayScore!,
      homeWin: fo?.homeWin,
      draw: fo?.draw,
      awayWin: fo?.awayWin,
    );
    totals[tip.userId] = totals[tip.userId]! + base + bonus;
  }
  return totals;
}

/// Platzierung (1-basiert) je Mitglied aus den Punkten. Gleiche Punktzahl =
/// gleicher Platz (Wettkampf-Ranking, z. B. 1, 2, 2, 4). Grundlage für die
/// Bewegungspfeile in der Tabelle (Vergleich Platz jetzt ↔ vorher).
Map<String, int> ranksByPoints(
  List<RoundMember> members,
  Map<String, int> totals,
) {
  final sorted = [...members]..sort((a, b) {
      final byPoints = (totals[b.userId] ?? 0) - (totals[a.userId] ?? 0);
      return byPoints != 0
          ? byPoints
          : a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });
  final ranks = <String, int>{};
  for (var i = 0; i < sorted.length; i++) {
    final id = sorted[i].userId;
    final samePointsAsPrev = i > 0 &&
        (totals[id] ?? 0) == (totals[sorted[i - 1].userId] ?? 0);
    ranks[id] = samePointsAsPrev ? ranks[sorted[i - 1].userId]! : i + 1;
  }
  return ranks;
}
