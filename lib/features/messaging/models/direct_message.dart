/// Eine 1:1-Direktnachricht zwischen zwei Nutzern (ligaübergreifend).
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;

  /// Die andere Partei aus Sicht von [me].
  String partnerOf(String me) => senderId == me ? recipientId : senderId;

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        recipientId: json['recipient_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
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
