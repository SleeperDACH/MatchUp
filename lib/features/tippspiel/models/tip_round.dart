import 'tip.dart';

/// Eine Tipprunde (à la Kicktipp): private Gruppe mit Einladungscode
/// und eigenem Punkteschema.
class TipRound {
  const TipRound({
    required this.id,
    required this.name,
    required this.leagueId,
    required this.season,
    required this.inviteCode,
    required this.scoring,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String leagueId;
  final int season;
  final String inviteCode;
  final ScoringRules scoring;
  final String createdBy;

  factory TipRound.fromJson(Map<String, dynamic> json) => TipRound(
        id: json['id'] as String,
        name: json['name'] as String,
        leagueId: json['league_id'] as String,
        season: json['season'] as int,
        inviteCode: json['invite_code'] as String,
        scoring: ScoringRules.fromJson(
            (json['scoring'] as Map<String, dynamic>?) ?? const {}),
        createdBy: json['created_by'] as String,
      );
}

/// Eine Zeile der Tipprunden-Rangliste.
class StandingsEntry {
  const StandingsEntry({
    required this.userId,
    required this.username,
    required this.points,
    required this.scoredTips,
  });

  final String userId;
  final String username;
  final int points;
  final int scoredTips;

  factory StandingsEntry.fromJson(Map<String, dynamic> json) => StandingsEntry(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        points: (json['points'] as num).toInt(),
        scoredTips: (json['scored_tips'] as num).toInt(),
      );
}
