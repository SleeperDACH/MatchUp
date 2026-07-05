/// Eine Chat-Nachricht im ligainternen Chat (Tippspiel wie Fantasy).
/// Der Anzeigename wird nicht mitgespeichert, sondern über die
/// Mitgliederliste der jeweiligen Liga aufgelöst.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String body;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
