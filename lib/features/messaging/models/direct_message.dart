/// Eine 1:1-Direktnachricht zwischen zwei Nutzern (ligaübergreifend).
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.tradeId,
    this.inviteLeagueId,
    this.inviteCode,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;

  /// Verknüpftes Trade-Angebot (falls die Nachricht eines begleitet).
  final String? tradeId;

  /// Verlinkte Fantasy-Liga + Einladungscode (falls es eine Liga-Einladung ist).
  final String? inviteLeagueId;
  final String? inviteCode;

  /// Ist die Nachricht eine tippbare Liga-Einladung?
  bool get isLeagueInvite =>
      inviteLeagueId != null && (inviteCode?.isNotEmpty ?? false);

  /// Die andere Partei aus Sicht von [me].
  String partnerOf(String me) => senderId == me ? recipientId : senderId;

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        recipientId: json['recipient_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        tradeId: json['trade_id'] as String?,
        inviteLeagueId: json['invite_league_id'] as String?,
        inviteCode: json['invite_code'] as String?,
      );
}

/// Kurzreferenz auf einen Nutzer (Profil) — für Suche und Namensauflösung.
class UserRef {
  const UserRef({required this.id, required this.username});

  final String id;
  final String username;

  factory UserRef.fromJson(Map<String, dynamic> json) => UserRef(
        id: json['id'] as String,
        username: json['username'] as String,
      );
}
