/// Ein strukturierter Transfer (Done Deal) aus Sportmonks.
class TransferDeal {
  const TransferDeal({
    required this.player,
    required this.fromTeam,
    required this.toTeam,
    required this.fromBundesliga,
    required this.toBundesliga,
    this.fromLogo,
    this.toLogo,
    this.date,
    this.amount,
    this.type,
  });

  final String player;
  final String fromTeam;
  final String toTeam;
  final bool fromBundesliga;
  final bool toBundesliga;
  final String? fromLogo;
  final String? toLogo;
  final DateTime? date;

  /// Ablöse in Euro (null = unbekannt/ablösefrei).
  final int? amount;
  final String? type;

  /// Anzeige der Ablöse: „€ 20 Mio.", „€ 1,6 Mio.", sonst Typ bzw. „ablösefrei".
  String get amountLabel {
    final a = amount;
    if (a != null && a > 0) {
      final mio = a / 1000000;
      final s = mio >= 10 || mio == mio.roundToDouble()
          ? mio.toStringAsFixed(0)
          : mio.toStringAsFixed(1).replaceAll('.', ',');
      return '€ $s Mio.';
    }
    final t = (type ?? '').toLowerCase();
    if (t.contains('loan') || t.contains('leih')) return 'Leihe';
    return 'ablösefrei';
  }

  factory TransferDeal.fromJson(Map<String, dynamic> json) => TransferDeal(
        player: (json['player'] as String? ?? '?').trim(),
        fromTeam: (json['from_team'] as String? ?? '—').trim(),
        toTeam: (json['to_team'] as String? ?? '—').trim(),
        fromBundesliga: json['from_bundesliga'] as bool? ?? false,
        toBundesliga: json['to_bundesliga'] as bool? ?? false,
        fromLogo: json['from_logo'] as String?,
        toLogo: json['to_logo'] as String?,
        date: (json['date'] as String?) != null
            ? DateTime.tryParse(json['date'] as String)
            : null,
        amount: (json['amount'] as num?)?.toInt(),
        type: json['type'] as String?,
      );
}
