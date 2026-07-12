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
    this.logoUrl,
    this.logoEmoji,
    this.logoColor,
  });

  final String id;
  final String name;
  final String leagueId;
  final int season;
  final String inviteCode;
  final ScoringRules scoring;
  final String createdBy;

  /// Runden-Logo ("Beides kombiniert"): Bild-URL oder Emoji + Farbe.
  final String? logoUrl;
  final String? logoEmoji;
  final String? logoColor;

  TipRound copyWith({ScoringRules? scoring}) => TipRound(
        id: id,
        name: name,
        leagueId: leagueId,
        season: season,
        inviteCode: inviteCode,
        scoring: scoring ?? this.scoring,
        createdBy: createdBy,
        logoUrl: logoUrl,
        logoEmoji: logoEmoji,
        logoColor: logoColor,
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
        logoUrl: json['logo_url'] as String?,
        logoEmoji: json['logo_emoji'] as String?,
        logoColor: json['logo_color'] as String?,
      );
}

/// Ein Mitglied einer Liga.
class RoundMember {
  const RoundMember({
    required this.userId,
    required this.username,
    this.teamName,
    this.avatarUrl,
    this.avatarEmoji,
    this.avatarColor,
  });

  final String userId;

  /// Globaler Nutzername (aus `profiles`).
  final String username;

  /// Ligaspezifischer Anzeigename; null/leer = kein eigener Name.
  final String? teamName;

  /// Profilbild (aus `profiles`): Bild-URL oder Emoji + Farbe.
  final String? avatarUrl;
  final String? avatarEmoji;
  final String? avatarColor;

  /// In der Liga anzuzeigender Name: Teamname, sonst der Nutzername.
  String get display =>
      (teamName?.trim().isNotEmpty ?? false) ? teamName!.trim() : username;

  factory RoundMember.fromJson(Map<String, dynamic> json) {
    final p = json['profiles'] as Map<String, dynamic>?;
    return RoundMember(
      userId: json['user_id'] as String,
      username: p?['username'] as String? ?? '?',
      teamName: json['team_name'] as String?,
      avatarUrl: p?['avatar_url'] as String?,
      avatarEmoji: p?['avatar_emoji'] as String?,
      avatarColor: p?['avatar_color'] as String?,
    );
  }
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

