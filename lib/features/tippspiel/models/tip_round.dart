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

  TipRound copyWith({ScoringRules? scoring}) => TipRound(
        id: id,
        name: name,
        leagueId: leagueId,
        season: season,
        inviteCode: inviteCode,
        scoring: scoring ?? this.scoring,
        createdBy: createdBy,
      );

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

/// Ein Mitglied einer Liga.
class RoundMember {
  const RoundMember({required this.userId, required this.username});

  final String userId;
  final String username;

  factory RoundMember.fromJson(Map<String, dynamic> json) => RoundMember(
        userId: json['user_id'] as String,
        username:
            (json['profiles'] as Map<String, dynamic>?)?['username'] as String? ??
                '?',
      );
}

/// Ein Tipp eines (beliebigen) Mitglieds — für die Tipp-Tabelle.
/// Fremde Tipps liefert der Server erst nach Anstoß (RLS).
class MemberTip {
  const MemberTip({
    required this.userId,
    required this.fixtureId,
    required this.homeGoals,
    required this.awayGoals,
  });

  final String userId;
  final String fixtureId;
  final int homeGoals;
  final int awayGoals;

  factory MemberTip.fromJson(Map<String, dynamic> json) => MemberTip(
        userId: json['user_id'] as String,
        fixtureId: json['fixture_id'] as String,
        homeGoals: json['home_goals'] as int,
        awayGoals: json['away_goals'] as int,
      );
}

