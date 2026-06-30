import 'models.dart';

/// Ein Tor im Spielverlauf (aus dem OpenLigaDB-Feed).
class MatchGoal {
  const MatchGoal({
    required this.minute,
    required this.scorer,
    required this.scoreHome,
    required this.scoreAway,
    required this.forHomeTeam,
    this.penalty = false,
    this.ownGoal = false,
  });

  /// Spielminute (kann fehlen, dann null).
  final int? minute;
  final String scorer;

  /// Spielstand nach diesem Tor.
  final int scoreHome;
  final int scoreAway;

  /// Hat die Heimmannschaft getroffen? (für die Ausrichtung in der Liste)
  final bool forHomeTeam;
  final bool penalty;
  final bool ownGoal;
}

/// Detailansicht eines Spiels: Ergebnis, Halbzeit, ggf. Verlängerung/Elfmeter,
/// Torschützen und Spielort. Reine Anzeige aus dem kostenlosen OpenLigaDB-Feed.
class MatchDetail {
  const MatchDetail({
    required this.id,
    required this.home,
    required this.away,
    required this.kickoff,
    required this.status,
    required this.homeScore,
    required this.awayScore,
    required this.goals,
    this.halfTime,
    this.afterExtraTime,
    this.penalties,
    this.stadium,
    this.city,
  });

  final String id;
  final TeamRef home;
  final TeamRef away;
  final DateTime kickoff;
  final FixtureStatus status;

  /// Maßgebliches Ergebnis (nach Verlängerung, sonst regulär) — null vor Anstoß.
  final int? homeScore;
  final int? awayScore;

  /// Zusatz-Ergebnisse, falls vorhanden.
  final (int, int)? halfTime;
  final (int, int)? afterExtraTime;
  final (int, int)? penalties;

  final List<MatchGoal> goals;
  final String? stadium;
  final String? city;

  bool get hasScore => homeScore != null && awayScore != null;
}
