/// Ein Torschütze in der Torjägerliste einer Liga (Quelle: Sportmonks).
class TopScorer {
  const TopScorer({
    required this.position,
    required this.playerName,
    required this.goals,
    this.playerImg,
    this.teamName,
    this.teamImg,
  });

  final int position;
  final String playerName;
  final int goals;
  final String? playerImg;
  final String? teamName;
  final String? teamImg;

  factory TopScorer.fromJson(Map<String, dynamic> j) => TopScorer(
        position: (j['position'] as num?)?.toInt() ?? 0,
        playerName: (j['player_name'] as String?) ?? '?',
        goals: (j['goals'] as num?)?.toInt() ?? 0,
        playerImg: j['player_img'] as String?,
        teamName: j['team_name'] as String?,
        teamImg: j['team_img'] as String?,
      );
}

/// Torjägerliste samt Hinweis, ob sie aus der laufenden ([current]) oder der
/// letzten abgeschlossenen Saison stammt (Fallback vor Saisonstart).
class TopScorersResult {
  const TopScorersResult(
      {required this.current, required this.scorers, this.seasonName});

  final bool current;
  final List<TopScorer> scorers;

  /// Name der Saison, aus der die Liste stammt (z. B. „2025/2026") — für den
  /// Fallback-Hinweis vor Saisonstart.
  final String? seasonName;
}
