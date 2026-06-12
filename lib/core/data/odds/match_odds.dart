/// Wettquoten zu einem Spiel (1X2 / h2h), als Dezimalquoten.
///
/// Anbieter-neutral; aktuell befüllt aus „The Odds API". [homeTeam] und
/// [awayTeam] sind die Namen der Quelle (englisch) — das Matching auf
/// die OpenLigaDB-Fixtures passiert im Odds-Layer.
class MatchOdds {
  const MatchOdds({
    required this.homeTeam,
    required this.awayTeam,
    required this.commenceTime,
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.bookmaker,
  });

  final String homeTeam;
  final String awayTeam;
  final DateTime commenceTime;

  /// Dezimalquote Heimsieg / Unentschieden / Auswärtssieg.
  final double homeWin;
  final double draw;
  final double awayWin;

  /// Name des Buchmachers, dessen Quote angezeigt wird.
  final String bookmaker;

  /// Dieselbe Quote mit vertauschter Heim-/Auswärtsperspektive — nötig,
  /// wenn der Quotenanbieter die Teams anders herum führt als OpenLigaDB.
  MatchOdds get swapped => MatchOdds(
        homeTeam: awayTeam,
        awayTeam: homeTeam,
        commenceTime: commenceTime,
        homeWin: awayWin,
        draw: draw,
        awayWin: homeWin,
        bookmaker: bookmaker,
      );
}
