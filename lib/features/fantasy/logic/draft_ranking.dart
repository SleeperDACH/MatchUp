import '../models/fantasy_models.dart';
import 'fantasy_scoring_rules.dart';

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
/// [rules]. Dient als Draft-Reihung „bester zuerst".
///
/// **Bewusst nur eine Näherung**, keine zweite Wertung: `player_season_totals`
/// kennt nur Einsätze, Tore, Vorlagen, Zu-Null und Karten — die feinen
/// Kategorien der Punktevergabe (Paraden, Zweikämpfe, Rating, Meilensteine)
/// stehen dort nicht. Für eine *Reihenfolge* reicht das; als Punktzahl wäre es
/// falsch, deshalb liegt die echte Wertung ausschließlich in [scorePlayer].
///
/// Die Einsatzpunkte werden mit der höchsten Stufe angesetzt, weil die
/// Saison-Summen keine Minuten je Spiel führen — das trifft Stammspieler
/// richtig und überschätzt Ergänzungsspieler leicht.
double projectedSeasonPoints(
  SeasonTotals t,
  PlayerPosition position, [
  FantasyScoringRules rules = FantasyScoringRules.standard,
]) {
  final perAppearance =
      rules.appearance.isEmpty ? 0.0 : rules.appearance.first.points;
  var pts = t.appearances * perAppearance;
  pts += t.goals * rules.goal;
  pts += t.assists * rules.assist;
  pts += t.cleanSheets * rules.cleanSheet.of(position);
  pts += t.yellow * rules.yellowCard;
  pts += t.red * rules.redCard;
  return pts;
}
