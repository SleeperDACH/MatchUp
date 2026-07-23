/// Reguläre Fantasy-Saison = Bundesliga-Spieltage.
const kRegularSeasonMatchdays = 34;

/// Berechneter Playoff-Plan aus den Liga-Einstellungen: wie viele Runden, an
/// welchem Spieltag die Playoffs starten und wann die Trade-Deadline liegt.
class PlayoffPlan {
  const PlayoffPlan({
    required this.teams,
    required this.weeksPerRound,
    required this.tradeDeadlineOffset,
    required this.rounds,
    required this.startRound,
    required this.tradeDeadlineRound,
    required this.topSeedBye,
    required this.totalMatchdays,
  });

  final int teams;
  final int weeksPerRound;

  /// Trade-Deadline in Spieltagen vor dem Playoff-Start (5–10).
  final int tradeDeadlineOffset;

  /// Anzahl Playoff-Runden.
  final int rounds;

  /// Erster Playoff-Spieltag.
  final int startRound;

  /// Spieltag der Trade-Deadline.
  final int tradeDeadlineRound;

  /// Ungerade Teamzahl → Platz 1 bekommt ein Freilos (Bye Week).
  final bool topSeedBye;

  final int totalMatchdays;

  /// Playoffs passen in die Saison (Start ≥ 2) und die Trade-Deadline liegt
  /// noch in der regulären Saison (≥ 1).
  bool get isValid => startRound >= 2 && tradeDeadlineRound >= 1;
}

/// Anzahl Playoff-Runden für [teams] Teams. Jede Runde halbiert das Feld
/// (bei ungerader Zahl kommt der Topgesetzte per Freilos weiter).
int playoffRounds(int teams) {
  var remaining = teams;
  var rounds = 0;
  while (remaining > 1) {
    remaining = (remaining + 1) ~/ 2;
    rounds++;
  }
  return rounds;
}

PlayoffPlan computePlayoffPlan({
  required int teams,
  required int weeksPerRound,
  required int tradeDeadlineOffset,
  int totalMatchdays = kRegularSeasonMatchdays,
  int? totalTeams,
}) {
  // Winner- und Loser-/Trost-Bracket laufen parallel über dieselben Spieltage.
  // Ist die Trost-Gruppe größer, braucht sie mehr Runden — das Fenster richtet
  // sich nach dem längeren der beiden Brackets, damit beide reinpassen.
  final winnerRounds = playoffRounds(teams);
  final consoRounds = (totalTeams != null && totalTeams > teams)
      ? playoffRounds(totalTeams - teams)
      : 0;
  final rounds = winnerRounds > consoRounds ? winnerRounds : consoRounds;
  final startRound = totalMatchdays - rounds * weeksPerRound + 1;
  return PlayoffPlan(
    teams: teams,
    weeksPerRound: weeksPerRound,
    tradeDeadlineOffset: tradeDeadlineOffset,
    rounds: rounds,
    startRound: startRound,
    tradeDeadlineRound: startRound - tradeDeadlineOffset,
    topSeedBye: teams.isOdd,
    totalMatchdays: totalMatchdays,
  );
}
