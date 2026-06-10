import '../models/fantasy_models.dart';

/// Adapter für die Fantasy-Spielerdaten — analog zu SportsDataProvider.
///
/// Trennt den Spielerpool (Kader, Alter, Nationalität) und später die
/// Live-Spielerpunkte vom Rest der App. Aktuell gibt es nur den
/// Seed-Pool ([SeedFantasyDataProvider]); eine echte Stats-Quelle
/// (für Kickbase-Stil-Punkte) wird später hier eingehängt, ohne dass
/// Draft, Kader oder UI angefasst werden müssen.
abstract class FantasyDataProvider {
  String get id;

  /// Alle wählbaren Spieler des Wettbewerbs.
  Future<List<FantasyPlayer>> getPlayerPool({required int season});

  /// Fantasy-Punkte eines Spielers an einem Spieltag (Kickbase-Stil).
  /// Liefert null, solange keine Live-Stats angebunden sind.
  Future<int?> getPlayerPoints({
    required String playerId,
    required int season,
    required int round,
  });
}
