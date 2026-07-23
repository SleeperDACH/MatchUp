/// Ein Treffer der öffentlichen Ligasuche (`search_public_leagues`). Vereint
/// Fantasy-Ligen und Tipprunden; [kind] unterscheidet beide. Enthält nur
/// unbedenkliche Felder plus den Status des Aufrufers.
class PublicLeagueResult {
  const PublicLeagueResult({
    required this.kind,
    required this.id,
    required this.name,
    required this.season,
    required this.memberCount,
    required this.joinPolicy,
    required this.joinable,
    required this.isMember,
    required this.requested,
    this.logoUrl,
    this.logoEmoji,
    this.logoColor,
    this.maxTeams,
  });

  /// `fantasy` oder `tip`.
  final String kind;
  final String id;
  final String name;
  final int season;
  final int memberCount;

  /// `open` (freier Eintritt) oder `invite` (Beitritt nur per Anfrage).
  final String joinPolicy;

  /// Direkt beitretbar (öffentlich + freier Eintritt, Fantasy zusätzlich vor
  /// Draft-Start).
  final bool joinable;
  final bool isMember;

  /// Der Aufrufer hat bereits eine Beitrittsanfrage gestellt (nur `invite`).
  final bool requested;

  final String? logoUrl;
  final String? logoEmoji;
  final String? logoColor;
  final int? maxTeams;

  bool get isFantasy => kind == 'fantasy';
  bool get isInviteOnly => joinPolicy == 'invite';

  /// Teilnehmerlimit erreicht (nur Fantasy hat ein Limit). Ein voller freier
  /// Beitritt ist gesperrt, bevor der Server-Fehler „voll" auftritt.
  bool get isFull => maxTeams != null && memberCount >= maxTeams!;

  factory PublicLeagueResult.fromJson(Map<String, dynamic> json) =>
      PublicLeagueResult(
        kind: json['kind'] as String,
        id: json['id'] as String,
        name: json['name'] as String,
        season: json['season'] as int,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        joinPolicy: json['join_policy'] as String? ?? 'open',
        joinable: json['joinable'] as bool? ?? false,
        isMember: json['is_member'] as bool? ?? false,
        requested: json['requested'] as bool? ?? false,
        logoUrl: json['logo_url'] as String?,
        logoEmoji: json['logo_emoji'] as String?,
        logoColor: json['logo_color'] as String?,
        maxTeams: (json['max_teams'] as num?)?.toInt(),
      );
}
