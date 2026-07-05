/// Status eines Trade-Angebots (entspricht der Server-Enum).
enum TradeStatus {
  pending('Offen'),
  accepted('Angenommen'),
  rejected('Abgelehnt'),
  cancelled('Zurückgezogen');

  const TradeStatus(this.label);

  final String label;

  bool get isPending => this == TradeStatus.pending;

  static TradeStatus fromId(String id) =>
      values.firstWhere((s) => s.name == id, orElse: () => TradeStatus.pending);
}

/// Ein Trade-Angebot zwischen zwei Managern einer Liga. Die einzelnen
/// Spieler stecken in [TradeItem]s (separate Tabelle, per [tradeId] verknüpft).
class TradeOffer {
  const TradeOffer({
    required this.id,
    required this.leagueId,
    required this.fromManager,
    required this.toManager,
    required this.status,
    required this.createdAt,
    this.message,
  });

  final String id;
  final String leagueId;
  final String fromManager;
  final String toManager;
  final TradeStatus status;
  final String? message;
  final DateTime createdAt;

  factory TradeOffer.fromJson(Map<String, dynamic> json) => TradeOffer(
        id: json['id'] as String,
        leagueId: json['league_id'] as String,
        fromManager: json['from_manager'] as String,
        toManager: json['to_manager'] as String,
        status: TradeStatus.fromId(json['status'] as String? ?? 'pending'),
        message: json['message'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Ein Spieler in einem Angebot: [giver] gibt [playerId] ab.
class TradeItem {
  const TradeItem({
    required this.tradeId,
    required this.giver,
    required this.playerId,
  });

  final String tradeId;
  final String giver;
  final String playerId;

  factory TradeItem.fromJson(Map<String, dynamic> json) => TradeItem(
        tradeId: json['trade_id'] as String,
        giver: json['giver'] as String,
        playerId: json['player_id'] as String,
      );
}
