/// Zum Anstoß eingefrorene 1X2-Quote eines Spiels — Grundlage für den
/// Quoten-Bonus in der Wertung. Wird serverseitig (Sync-Job) pro Fixture
/// gespeichert (Tabelle `fixture_odds`), damit die Wertung stabil bleibt,
/// auch wenn sich die Live-Quoten danach ändern.
class FrozenOdds {
  const FrozenOdds({
    required this.fixtureId,
    required this.homeWin,
    required this.draw,
    required this.awayWin,
  });

  final String fixtureId;

  /// Dezimalquote Heimsieg / Unentschieden / Auswärtssieg zum Anstoß.
  final double homeWin;
  final double draw;
  final double awayWin;

  factory FrozenOdds.fromJson(Map<String, dynamic> json) => FrozenOdds(
        fixtureId: json['fixture_id'] as String,
        homeWin: (json['home_win'] as num).toDouble(),
        draw: (json['draw'] as num).toDouble(),
        awayWin: (json['away_win'] as num).toDouble(),
      );
}
