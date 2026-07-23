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

/// Ein Spieler in der Aufstellung (Startelf oder Bank).
class LineupPlayer {
  const LineupPlayer({
    required this.name,
    required this.forHomeTeam,
    required this.starting,
    this.playerId,
    this.number,
    this.position,
    this.row,
    this.col,
  });

  final String name;
  final bool forHomeTeam;
  final bool starting;
  final int? playerId;
  final int? number;

  /// Formationsposition (1 = Torwart …), null bei Bankspielern.
  final int? position;

  /// Rasterposition auf dem Feld (Reihe 1 = Tor … / Spalte innerhalb der Reihe),
  /// aus Sportmonks `formation_field` ("row:col"); null bei Bankspielern.
  final int? row;
  final int? col;
}

/// Eine Statistikzeile mit Heim-/Auswärtswert (z. B. Ballbesitz %).
class MatchStat {
  const MatchStat({required this.label, required this.home, required this.away});
  final String label;
  final num home;
  final num away;
}

/// Ein Ereignis im Spielverlauf (Tor, Karte, Wechsel, VAR).
class MatchEvent {
  const MatchEvent({
    required this.minute,
    required this.type,
    required this.forHomeTeam,
    this.extra,
    this.player,
    this.playerId,
    this.related,
    this.result,
  });

  final int minute;
  final int? extra;

  /// Sportmonks-Typname: „Goal", „Yellowcard", „Redcard", „Substitution", „VAR".
  final String type;
  final bool forHomeTeam;
  final String? player;
  final int? playerId;
  final String? related;
  final String? result;
}

/// Detailansicht eines Spiels: Ergebnis, Torschützen, Spielverlauf,
/// Aufstellungen, Statistiken und Spielort (Quelle: Sportmonks).
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
    this.leagueKey,
    this.homeFormation,
    this.awayFormation,
    this.lineups = const [],
    this.stats = const [],
    this.events = const [],
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

  /// Sportmonks-Liga-ID (für die Live-Tabelle).
  final String? leagueKey;

  /// Formation je Team (z. B. „4-2-3-1"), falls verfügbar.
  final String? homeFormation;
  final String? awayFormation;
  final List<LineupPlayer> lineups;
  final List<MatchStat> stats;
  final List<MatchEvent> events;

  bool get hasScore => homeScore != null && awayScore != null;
}
