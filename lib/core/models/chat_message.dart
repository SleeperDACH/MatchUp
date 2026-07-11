/// Eine Chat-Nachricht im ligainternen Chat (Tippspiel wie Fantasy).
/// Der Anzeigename wird nicht mitgespeichert, sondern über die
/// Mitgliederliste der jeweiligen Liga aufgelöst.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.isSystem = false,
    this.tradeId,
    this.replyTo,
  });

  final String id;

  /// Absender-ID; `null` bei automatischen System-Nachrichten.
  final String? userId;
  final String body;
  final DateTime createdAt;

  /// Automatische Mitteilung (z. B. Kaderänderung) — ohne Absender, wird
  /// als dezente Zeile statt als Sprechblase dargestellt.
  final bool isSystem;

  /// Verknüpftes Trade-Angebot (nur Direktnachrichten) — der Chat rendert
  /// dann eine Aktionskarte zum Annehmen/Ablehnen.
  final String? tradeId;

  /// ID der Nachricht, auf die geantwortet wird (`null` = keine Antwort).
  final String? replyTo;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        userId: json['user_id'] as String?,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        isSystem: json['is_system'] as bool? ?? false,
        tradeId: json['trade_id'] as String?,
        replyTo: json['reply_to'] as String?,
      );
}
