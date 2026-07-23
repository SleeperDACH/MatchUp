import '../models/fantasy_models.dart';

/// Rohe Saison-Aggregate eines Spielers (aus `player_season_totals`).
class SeasonTotals {
  const SeasonTotals({
    this.goals = 0,
    this.assists = 0,
    this.minutes = 0,
    this.yellow = 0,
    this.red = 0,
    this.cleanSheets = 0,
    this.appearances = 0,
  });

  final int goals;
  final int assists;
  final int minutes;
  final int yellow;
  final int red;
  final int cleanSheets;
  final int appearances;

  factory SeasonTotals.fromJson(Map<String, dynamic> json) => SeasonTotals(
        goals: json['goals'] as int? ?? 0,
        assists: json['assists'] as int? ?? 0,
        minutes: json['minutes'] as int? ?? 0,
        yellow: json['yellow'] as int? ?? 0,
        red: json['red'] as int? ?? 0,
        cleanSheets: json['clean_sheets'] as int? ?? 0,
        appearances: json['appearances'] as int? ?? 0,
      );
}

/// Hochgerechnete Fantasy-Punkte einer kompletten Saison für [position] unter
/// [scoring] — gleiche Formel wie [scorePlayer], nur über die Saison-Summen.
/// Dient als Draft-Reihung „bester zuerst".
int projectedSeasonPoints(
    SeasonTotals t, PlayerPosition position, FantasyScoring scoring) {
  final goalPts = switch (position) {
    PlayerPosition.gk => scoring.goalGk,
    PlayerPosition.def => scoring.goalDef,
    PlayerPosition.mid => scoring.goalMid,
    PlayerPosition.fwd => scoring.goalFwd,
  };
  var pts = t.appearances * scoring.appearance;
  pts += t.goals * goalPts;
  pts += t.assists * scoring.assist;
  if (position == PlayerPosition.gk || position == PlayerPosition.def) {
    pts += t.cleanSheets * scoring.cleanSheetGkDef;
  }
  pts += t.yellow * scoring.yellowCard;
  pts += t.red * scoring.redCard;
  return pts;
}
