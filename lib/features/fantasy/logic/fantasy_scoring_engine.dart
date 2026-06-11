import '../models/fantasy_models.dart';

/// Leistungsdaten eines Spielers an einem Spieltag — die Form, die ein
/// echter Stats-Feed liefern würde. Aktuell füllt der OpenLigaDB-Adapter
/// nur [goals], [cleanSheet] und [played]; Assists/Karten kommen mit
/// einem vollständigen Feed dazu.
class PlayerMatchStats {
  const PlayerMatchStats({
    this.goals = 0,
    this.assists = 0,
    this.played = false,
    this.cleanSheet = false,
    this.yellow = 0,
    this.red = 0,
    this.minutes = 0,
  });

  final int goals;
  final int assists;
  final bool played;
  final bool cleanSheet;
  final int yellow;
  final int red;

  /// Einsatzminuten (0, solange nur OpenLigaDB die Quelle ist).
  final int minutes;

  bool get hasContribution =>
      played || goals > 0 || assists > 0 || cleanSheet || yellow > 0 || red > 0;

  /// Aus einer Zeile der Tabelle player_match_stats (serverseitiger Feed).
  factory PlayerMatchStats.fromDb(Map<String, dynamic> r) {
    final goals = r['goals'] as int? ?? 0;
    final minutes = r['minutes'] as int? ?? 0;
    return PlayerMatchStats(
      goals: goals,
      assists: r['assists'] as int? ?? 0,
      minutes: minutes,
      played: (r['appeared'] as bool?) ?? (minutes > 0 || goals > 0),
      cleanSheet: r['clean_sheet'] as bool? ?? false,
      yellow: r['yellow'] as int? ?? 0,
      red: r['red'] as int? ?? 0,
    );
  }
}

/// Fantasy-Punkte eines Spielers (Kickbase-Stil, über [FantasyScoring]
/// konfigurierbar). Pure Funktion — identisch im Client und später in
/// einer Server-Aggregation nachbaubar.
int scorePlayer(
    PlayerMatchStats s, PlayerPosition position, FantasyScoring scoring) {
  var pts = 0;
  if (s.played) pts += scoring.appearance;
  final goalPts = switch (position) {
    PlayerPosition.gk => scoring.goalGk,
    PlayerPosition.def => scoring.goalDef,
    PlayerPosition.mid => scoring.goalMid,
    PlayerPosition.fwd => scoring.goalFwd,
  };
  pts += s.goals * goalPts;
  pts += s.assists * scoring.assist;
  if (s.cleanSheet &&
      (position == PlayerPosition.gk || position == PlayerPosition.def)) {
    pts += scoring.cleanSheetGkDef;
  }
  pts += s.yellow * scoring.yellowCard;
  pts += s.red * scoring.redCard;
  return pts;
}

/// Ergebnis der automatischen Startelf-Bildung.
class Lineup {
  const Lineup({required this.starterIds, required this.total});

  final Set<String> starterIds;
  final int total;
}

/// Beste Startelf aus den gedrafteten Spielern nach Punkten dieses
/// Spieltags (Formation aus [RosterConfig]). Approximiert das
/// Kickbase-Prinzip „deine elf Besten zählen", solange es noch keine
/// manuelle Aufstellung gibt. Bench-Spieler zählen nicht.
Lineup bestEleven(Map<FantasyPlayer, int> points, RosterConfig roster) {
  final byPos = <PlayerPosition, List<MapEntry<FantasyPlayer, int>>>{};
  points.forEach((player, pts) =>
      byPos.putIfAbsent(player.position, () => []).add(MapEntry(player, pts)));
  for (final list in byPos.values) {
    list.sort((a, b) => b.value.compareTo(a.value));
  }
  final slots = {
    PlayerPosition.gk: roster.gk,
    PlayerPosition.def: roster.def,
    PlayerPosition.mid: roster.mid,
    PlayerPosition.fwd: roster.fwd,
  };
  final starters = <String>{};
  var total = 0;
  slots.forEach((pos, n) {
    final list = byPos[pos] ?? const [];
    for (var i = 0; i < n && i < list.length; i++) {
      starters.add(list[i].key.id);
      total += list[i].value;
    }
  });
  return Lineup(starterIds: starters, total: total);
}

/// Aufstellung aus einer manuell gewählten Starter-Menge: summiert die
/// Punkte der gewählten Spieler (Bank zählt nicht). Spieler in
/// [starterIds], die nicht (mehr) im Kader sind, werden ignoriert.
Lineup chosenLineup(Map<FantasyPlayer, int> points, Set<String> starterIds) {
  final starters = <String>{};
  var total = 0;
  points.forEach((player, pts) {
    if (starterIds.contains(player.id)) {
      starters.add(player.id);
      total += pts;
    }
  });
  return Lineup(starterIds: starters, total: total);
}

/// Effektive Aufstellung eines Spieltags: die manuell gewählte Startelf,
/// falls vorhanden, sonst die automatische beste Elf.
Lineup effectiveLineup(
  Map<FantasyPlayer, int> points,
  RosterConfig roster,
  Set<String>? manualStarterIds,
) {
  if (manualStarterIds != null && manualStarterIds.isNotEmpty) {
    return chosenLineup(points, manualStarterIds);
  }
  return bestEleven(points, roster);
}
