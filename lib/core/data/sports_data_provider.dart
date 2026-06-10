import '../models/models.dart';

/// Adapter-Interface für Sportdaten-Quellen.
///
/// Pro Liga steckt hinter diesem Interface ein anderer Anbieter
/// (OpenLigaDB für die Bundesliga, später z. B. api-football für die
/// Premier League oder ein NFL-Provider). Der Rest der App arbeitet
/// ausschließlich gegen dieses Interface.
abstract class SportsDataProvider {
  String get id;

  /// Nummer der aktuell laufenden bzw. nächsten Runde (Spieltag/Week).
  Future<int> getCurrentRound(LeagueInfo league, int season);

  /// Alle Runden des Wettbewerbs mit offiziellen Namen — bei Turnieren
  /// inklusive der K.o.-Runden, auch wenn deren Paarungen noch nicht
  /// feststehen.
  Future<List<RoundInfo>> getRounds(LeagueInfo league, int season);

  /// Alle Spiele einer Runde.
  Future<List<Fixture>> getRoundFixtures(LeagueInfo league, int season, int round);

  /// Alle Spiele einer Saison (für Punkteberechnung über die ganze Saison).
  Future<List<Fixture>> getSeasonFixtures(LeagueInfo league, int season);
}
