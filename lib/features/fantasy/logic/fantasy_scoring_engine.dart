import 'dart:math';

import '../models/fantasy_models.dart';
import 'fantasy_scoring_rules.dart';

/// Roh-Leistungsdaten eines Spielers an einem Spieltag.
///
/// Ein Feld je Zählwert der Punktevergabe — die Felder entsprechen exakt
/// `PlayerEvents` in `scoring/src/types.ts` und den Spalten von
/// `public.player_match_stats` (Migration 0074). Roh-Stats, keine Punkte.
class PlayerMatchStats {
  const PlayerMatchStats({
    this.minutes = 0,
    this.goals = 0,
    this.penaltyGoals = 0,
    this.assists = 0,
    this.bigChancesCreated = 0,
    this.keyPasses = 0,
    this.accuratePasses = 0,
    this.shotsOnTarget = 0,
    this.successfulDribbles = 0,
    this.goalsConceded = 0,
    this.saves = 0,
    this.penaltiesSaved = 0,
    this.tacklesWon = 0,
    this.interceptions = 0,
    this.ballRecovery = 0,
    this.clearances = 0,
    this.blockedShots = 0,
    this.yellow = 0,
    this.secondYellow = 0,
    this.red = 0,
    this.ownGoals = 0,
    this.penaltiesMissed = 0,
    this.errorsLeadToGoal = 0,
    this.bigChancesMissed = 0,
    this.offsides = 0,
    this.fouls = 0,
    this.possessionLost = 0,
    this.rating,
    this.played = false,
    this.cleanSheet = false,
    this.fullStats = false,
  });

  final int minutes;
  final int goals;

  /// Davon per Elfmeter — in [goals] bereits enthalten.
  final int penaltyGoals;
  final int assists;
  final int bigChancesCreated;

  /// Gesamt, inklusive der zu Großchancen führenden.
  final int keyPasses;

  /// Genaue Pässe (Sportmonks `accurate-passes`). Basis der Pass-Boni.
  final int accuratePasses;
  final int shotsOnTarget;
  final int successfulDribbles;
  final int goalsConceded;
  final int saves;
  final int penaltiesSaved;
  final int tacklesWon;
  /// Abgefangene Bälle. **Nicht** dasselbe wie [ballRecovery] —
  /// Interceptions sind rund viermal seltener.
  final int interceptions;

  /// Balleroberungen (Sportmonks `ball-recovery`).
  final int ballRecovery;
  final int clearances;
  final int blockedShots;
  final int yellow;
  final int secondYellow;
  final int red;
  final int ownGoals;
  final int penaltiesMissed;
  final int errorsLeadToGoal;
  final int bigChancesMissed;
  final int offsides;
  final int fouls;
  final int possessionLost;

  /// Sportmonks-Rating 0–10. `null` heißt „keine Wertung vergeben" — das ist
  /// nicht dasselbe wie 0 und darf keinen Rating-Malus auslösen.
  final double? rating;

  final bool played;

  /// Bequemlichkeits-Spiegel des Feeds. Maßgeblich für die Wertung sind
  /// [goalsConceded] und [minutes]; die Schwelle steht in den Regeln.
  final bool cleanSheet;

  /// Stammt die Zeile aus dem vollständigen Sportmonks-Satz? Bei `false`
  /// (OpenLigaDB-Notfall) sind nur [goals] und [cleanSheet] belastbar — alle
  /// übrigen Zähler stehen auf 0, weil die Quelle sie nicht kennt, nicht weil
  /// der Spieler nichts getan hätte.
  final bool fullStats;

  bool get hasContribution =>
      played || minutes > 0 || goals > 0 || assists > 0 || cleanSheet;

  /// Aus einer Zeile der Tabelle `player_match_stats`.
  factory PlayerMatchStats.fromDb(Map<String, dynamic> r) {
    int i(String k) => (r[k] as num?)?.toInt() ?? 0;
    final minutes = i('minutes');
    final goals = i('goals');
    return PlayerMatchStats(
      minutes: minutes,
      goals: goals,
      penaltyGoals: i('penalty_goals'),
      assists: i('assists'),
      bigChancesCreated: i('big_chances_created'),
      keyPasses: i('key_passes'),
      accuratePasses: i('accurate_passes'),
      shotsOnTarget: i('shots_on_target'),
      successfulDribbles: i('successful_dribbles'),
      goalsConceded: i('goals_conceded'),
      saves: i('saves'),
      penaltiesSaved: i('penalties_saved'),
      tacklesWon: i('tackles_won'),
      interceptions: i('interceptions'),
      ballRecovery: i('ball_recovery'),
      clearances: i('clearances'),
      blockedShots: i('blocked_shots'),
      yellow: i('yellow'),
      secondYellow: i('second_yellow'),
      red: i('red'),
      ownGoals: i('own_goals'),
      penaltiesMissed: i('penalties_missed'),
      errorsLeadToGoal: i('errors_lead_to_goal'),
      bigChancesMissed: i('big_chances_missed'),
      offsides: i('offsides'),
      fouls: i('fouls'),
      possessionLost: i('possession_lost'),
      rating: (r['rating'] as num?)?.toDouble(),
      played: (r['appeared'] as bool?) ?? (minutes > 0 || goals > 0),
      cleanSheet: r['clean_sheet'] as bool? ?? false,
      fullStats: (r['source'] as String?) != 'openligadb',
    );
  }
}

/// Eine Zeile der Punkte-Aufschlüsselung für die Anzeige.
class ScoreLine {
  const ScoreLine(this.label, this.count, this.pointsEach);
  final String label;
  final int count;
  final double pointsEach;
  double get subtotal => count * pointsEach;
}

/// Punkte eines Spielers für ein Spiel, aufgeschlüsselt.
class PlayerScore {
  const PlayerScore(this.total, this.breakdown);
  final double total;
  final List<ScoreLine> breakdown;
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Kumulative Meilenstein-Boni: die Boni **aller** erreichten Schwellen.
List<Milestone> reachedMilestones(int count, List<Milestone> thresholds) =>
    [for (final t in thresholds) if (count >= t.atLeast) t];

/// Fantasy-Punkte eines Spielers, aufgeschlüsselt.
///
/// Pure Funktion, ohne Abhängigkeiten — dieselbe Wertung existiert ein zweites
/// Mal als TypeScript-Modul unter `scoring/`; bei Änderungen beide anpassen.
PlayerScore scorePlayerDetailed(
  PlayerMatchStats s,
  PlayerPosition position, [
  FantasyScoringRules rules = FantasyScoringRules.standard,
]) {
  final lines = <ScoreLine>[];
  void push(String label, int count, double each) {
    if (count == 0 || each == 0) return;
    lines.add(ScoreLine(label, count, each));
  }

  // Einsatz — höchste erreichte Stufe. **Je Position:** Torhüter haben keine
  // Stufen, weil der Sockel bei ihnen eine Konstante wäre (sie spielen
  // praktisch immer 90 Minuten).
  for (final tier in rules.einsatz(position)) {
    if (s.minutes >= tier.atLeastMinutes) {
      lines.add(ScoreLine(tier.label, 1, tier.points));
      break;
    }
  }

  // Offensive. Elfmetertore zählen separat und dürfen nicht doppelt in die
  // regulären Tore fallen.
  push('Tor', s.goals - s.penaltyGoals < 0 ? 0 : s.goals - s.penaltyGoals,
      rules.goal);
  push('Tor (Elfmeter)', s.penaltyGoals, rules.penaltyGoal);
  push('Vorlage', s.assists, rules.assist);
  push('Großchance kreiert', s.bigChancesCreated, rules.bigChanceCreated);
  // Großchancen sind in den Key Passes enthalten und oben schon höher
  // bewertet — hier nur der Rest, sonst zählt dieselbe Aktion zweimal.
  final keyPassesNet = s.keyPasses - s.bigChancesCreated;
  push('Key Pass', keyPassesNet < 0 ? 0 : keyPassesNet, rules.keyPass);
  push('Schuss aufs Tor', s.shotsOnTarget, rules.shotOnTarget);
  push('Erfolgreiches Dribbling', s.successfulDribbles,
      rules.successfulDribble);

  // Defensive
  final csPts = rules.cleanSheet.of(position);
  if (csPts != 0 &&
      s.minutes >= rules.cleanSheetMinMinutes &&
      s.goalsConceded == 0) {
    lines.add(ScoreLine('Zu Null', 1, csPts));
  }
  push('Gegentor', s.goalsConceded, rules.goalConceded.of(position));
  push('Parade', s.saves, rules.save);
  push('Gehaltener Elfmeter', s.penaltiesSaved, rules.penaltySaved);
  push('Tackling gewonnen', s.tacklesWon, rules.tackleWon.of(position));
  // **„Balleroberung" hieß früher diese Zeile** — sie zählt aber
  // abgefangene Bälle. Der Name gehört zum Feld darunter.
  push('Abgefangener Ball', s.interceptions,
      rules.interception.of(position));
  push('Balleroberung', s.ballRecovery, rules.ballRecovery.of(position));
  push('Klärung', s.clearances, rules.clearance.of(position));
  push('Geblockter Schuss', s.blockedShots, rules.blockedShot.of(position));

  // Meilensteine
  if (position == PlayerPosition.gk) {
    for (final m in reachedMilestones(s.saves, rules.saveMilestones)) {
      lines.add(ScoreLine('Paraden-Meilenstein (≥${m.atLeast})', 1, m.bonus));
    }
  }
  final defCount =
      s.tacklesWon + s.interceptions + s.clearances + s.blockedShots;
  for (final m in reachedMilestones(
      defCount, rules.defensiveMilestones[position] ?? const [])) {
    lines.add(ScoreLine('Defensiv-Meilenstein (≥${m.atLeast})', 1, m.bonus));
  }
  // Genaue Pässe — Schwellen je Position, siehe `passMilestones`.
  for (final m in reachedMilestones(
      s.accuratePasses, rules.passMilestones[position] ?? const [])) {
    lines.add(ScoreLine('Pass-Meilenstein (≥${m.atLeast})', 1, m.bonus));
  }

  // Negativ
  push('Gelbe Karte', s.yellow, rules.yellowCard);
  push('Gelb-Rot (zusätzlich)', s.secondYellow, rules.secondYellow);
  push('Rote Karte', s.red, rules.redCard);
  push('Eigentor', s.ownGoals, rules.ownGoal);
  push('Verschossener Elfmeter', s.penaltiesMissed, rules.penaltyMissed);
  push('Fehler vor Gegentor', s.errorsLeadToGoal, rules.errorLeadToGoal);
  push('Großchance vergeben', s.bigChancesMissed, rules.bigChanceMissed);
  push('Abseits', s.offsides, rules.offside);
  push('Foul', s.fouls, rules.foul);
  push('Ballverlust', s.possessionLost, rules.possessionLost);

  // Rating-Bonus — nur wenn überhaupt eine Wertung vorliegt.
  final rating = s.rating;
  if (rating != null) {
    for (final (atLeast, pts) in rules.ratingTiers) {
      if (rating >= atLeast) {
        if (pts != 0) {
          lines.add(
              ScoreLine('Rating-Bonus (${rating.toStringAsFixed(1)})', 1, pts));
        }
        break;
      }
    }
  }

  final total =
      _round2(lines.fold<double>(0, (sum, l) => sum + l.subtotal));
  return PlayerScore(total, lines);
}

/// Punkte eines Spielers als Zahl (ohne Aufschlüsselung).
double scorePlayer(
  PlayerMatchStats s,
  PlayerPosition position, [
  FantasyScoringRules rules = FantasyScoringRules.standard,
]) =>
    scorePlayerDetailed(s, position, rules).total;

/// Ergebnis der automatischen Startelf-Bildung.
class Lineup {
  const Lineup({required this.starterIds, required this.total});

  final Set<String> starterIds;
  final double total;
}

/// Beste Startelf aus den gedrafteten Spielern nach Punkten dieses
/// Spieltags. Mit **flexibler Formation** (Min/Max je Position aus
/// [RosterConfig]) wird die punktbeste *gültige* Formation gewählt — das
/// Kickbase-Prinzip „deine elf Besten in einer erlaubten Aufstellung".
/// Bench-Spieler zählen nicht.
Lineup bestEleven(Map<FantasyPlayer, double> points, RosterConfig roster) {
  final byPos = <PlayerPosition, List<MapEntry<FantasyPlayer, double>>>{};
  points.forEach((player, pts) =>
      byPos.putIfAbsent(player.position, () => []).add(MapEntry(player, pts)));
  for (final list in byPos.values) {
    list.sort((a, b) => b.value.compareTo(a.value));
  }

  List<MapEntry<FantasyPlayer, double>> list(PlayerPosition p) =>
      byPos[p] ?? const [];
  double sumTop(PlayerPosition p, int n) {
    final l = list(p);
    var s = 0.0;
    for (var i = 0; i < n && i < l.length; i++) {
      s += l[i].value;
    }
    return s;
  }

  // Beste gültige Formation suchen: Torwart fix, Feldspieler in ihrer Spanne,
  // Summe = starters, und genug Spieler je Position vorhanden.
  final outfield = roster.starters - roster.gk;
  var bestTotal = double.negativeInfinity;
  var bestDef = 0, bestMid = 0, bestFwd = 0;
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
  var total = 0.0;
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
/// Punkte der gewählten Spieler (Bank zählt nicht).
///
/// **Wer hier fehlt, zählt nicht** — deshalb muss [points] jeden Aufgestellten
/// enthalten, auch einen, der den Kader inzwischen verlassen hat. Bis dahin
/// stand an dieser Stelle „Spieler, die nicht mehr im Kader sind, werden
/// ignoriert", und das war genau der Fehler: Ein Trade nach dem Anpfiff nahm
/// dem Abgeber rückwirkend die Punkte weg. Dafür sorgt
/// [effectiveTotalsForRound].
Lineup chosenLineup(
    Map<FantasyPlayer, double> points, Set<String> starterIds) {
  final starters = <String>{};
  var total = 0.0;
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
  Map<FantasyPlayer, double> points,
  RosterConfig roster,
  Set<String>? manualStarterIds,
) {
  if (manualStarterIds != null && manualStarterIds.isNotEmpty) {
    return chosenLineup(points, manualStarterIds);
  }
  return bestEleven(points, roster);
}

/// Effektive Startelf-Punkte aller Manager für einen Spieltag [round]
/// (manuelle Aufstellung, sonst automatisch beste Elf). Grundlage für die
/// Liga-Tabelle und die Head-to-Head-Bilanz.
Map<String, double> effectiveTotalsForRound({
  required Map<String, PlayerMatchStats> stats,
  required int round,
  required List<FantasyManager> managers,
  required List<RosterEntry> roster,
  required Map<String, FantasyPlayer> playerById,
  required List<FantasyLineup> lineups,
  FantasyScoringRules scoring = FantasyScoringRules.standard,
  required RosterConfig rosterConfig,
}) {
  final out = <String, double>{};
  for (final m in managers) {
    // Kaderlimit überschritten → keine Punkte, bis genug Spieler abgegeben
    // werden (verhindert, dass man sich per Trade unerlaubt viele Spieler holt).
    if (isRosterOverLimit(m.userId, roster, rosterConfig)) {
      out[m.userId] = 0.0;
      continue;
    }
    Set<String>? manual;
    for (final l in lineups) {
      if (l.round == round && l.managerId == m.userId) {
        manual = l.playerIds;
        break;
      }
    }
    // **Kader plus gestellte Elf.** Wer zum Anpfiff aufgestellt war, punktet
    // für diesen Spieltag — auch wenn er den Kader danach verlassen hat.
    // Vorher kam die Liste allein aus dem Kader von *jetzt*, und ein Trade
    // nach dem Anpfiff verschob die Punkte rückwirkend.
    final ids = <String>{
      for (final r in roster)
        if (r.managerId == m.userId) r.playerId,
      ...?manual,
    };
    final players = [
      for (final id in ids)
        if (playerById[id] != null) playerById[id]!,
    ];
    final points = {
      for (final p in players)
        p: scorePlayer(
            stats[p.id] ?? const PlayerMatchStats(), p.position, scoring)
    };
    out[m.userId] = effectiveLineup(points, rosterConfig, manual).total;
  }
  return out;
}

/// Anzahl Spieler im Kader von [managerId].
int rosterCountOf(String managerId, List<RosterEntry> roster) =>
    roster.where((r) => r.managerId == managerId).length;

/// Ob [managerId] mehr Spieler im Kader hat als erlaubt
/// ([RosterConfig.squadSize]). Über dem Limit gibt es keine Punkte, bis genug
/// Spieler abgegeben wurden.
bool isRosterOverLimit(
        String managerId, List<RosterEntry> roster, RosterConfig config) =>
    rosterCountOf(managerId, roster) > config.squadSize;

/// Punkte für die Anzeige. Die Wertung kennt Bruchteile (1,5 je Key Pass,
/// −0,4 je Foul), die meisten Summen sind aber glatt — deshalb ganze Zahlen
/// ohne Nachkommastelle und nur sonst eine.
String formatPoints(double v) {
  final r = (v * 10).roundToDouble() / 10;
  return r == r.roundToDouble()
      ? r.toStringAsFixed(0)
      : r.toStringAsFixed(1).replaceAll('.', ',');
}
