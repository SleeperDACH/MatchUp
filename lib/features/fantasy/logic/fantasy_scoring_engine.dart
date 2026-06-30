import 'dart:math';

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
/// Spieltags. Mit **flexibler Formation** (Min/Max je Position aus
/// [RosterConfig]) wird die punktbeste *gültige* Formation gewählt — das
/// Kickbase-Prinzip „deine elf Besten in einer erlaubten Aufstellung".
/// Bench-Spieler zählen nicht.
Lineup bestEleven(Map<FantasyPlayer, int> points, RosterConfig roster) {
  final byPos = <PlayerPosition, List<MapEntry<FantasyPlayer, int>>>{};
  points.forEach((player, pts) =>
      byPos.putIfAbsent(player.position, () => []).add(MapEntry(player, pts)));
  for (final list in byPos.values) {
    list.sort((a, b) => b.value.compareTo(a.value));
  }

  List<MapEntry<FantasyPlayer, int>> list(PlayerPosition p) =>
      byPos[p] ?? const [];
  int sumTop(PlayerPosition p, int n) {
    final l = list(p);
    var s = 0;
    for (var i = 0; i < n && i < l.length; i++) {
      s += l[i].value;
    }
    return s;
  }

  // Beste gültige Formation suchen: Torwart fix, Feldspieler in ihrer Spanne,
  // Summe = starters, und genug Spieler je Position vorhanden.
  final outfield = roster.starters - roster.gk;
  var bestTotal = -1, bestDef = 0, bestMid = 0, bestFwd = 0;
  var found = false;
  for (var d = roster.defMin; d <= roster.defMax; d++) {
    for (var m = roster.midMin; m <= roster.midMax; m++) {
      final f = outfield - d - m;
      if (f < roster.fwdMin || f > roster.fwdMax) continue;
      if (d > list(PlayerPosition.def).length ||
          m > list(PlayerPosition.mid).length ||
          f > list(PlayerPosition.fwd).length ||
          roster.gk > list(PlayerPosition.gk).length) {
        continue;
      }
      final t = sumTop(PlayerPosition.gk, roster.gk) +
          sumTop(PlayerPosition.def, d) +
          sumTop(PlayerPosition.mid, m) +
          sumTop(PlayerPosition.fwd, f);
      if (t > bestTotal) {
        bestTotal = t;
        bestDef = d;
        bestMid = m;
        bestFwd = f;
        found = true;
      }
    }
  }

  if (!found) {
    // Degenerierter Kader (zu wenige auf einer Position für eine gültige
    // Formation): best effort innerhalb der Maxima füllen.
    bestDef = min(list(PlayerPosition.def).length, roster.defMax);
    bestMid = min(list(PlayerPosition.mid).length, roster.midMax);
    bestFwd = min(list(PlayerPosition.fwd).length, roster.fwdMax);
  }

  final counts = {
    PlayerPosition.gk: roster.gk,
    PlayerPosition.def: bestDef,
    PlayerPosition.mid: bestMid,
    PlayerPosition.fwd: bestFwd,
  };
  final starters = <String>{};
  var total = 0;
  counts.forEach((pos, n) {
    final l = list(pos);
    for (var i = 0; i < n && i < l.length; i++) {
      starters.add(l[i].key.id);
      total += l[i].value;
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
