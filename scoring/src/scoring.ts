// Fantasy-Scoring: reine Punktberechnung aus internen PlayerEvents. Alle Werte
// stammen aus scoring.config.json — keine Magic Numbers im Code.

import cfg from '../config/scoring.config.json';
import { BreakdownLine, Player, PlayerEvents, Position, ScoreResult } from './types';

const round = (n: number) => Math.round(n * 100) / 100;

interface Threshold { atLeast: number; bonus: number; }

/**
 * Kumulative Meilenstein-Boni: summiert die Boni aller erreichten Schwellen.
 * Schwellen kommen aus der Config, nichts ist hier hartkodiert.
 */
export function milestoneBonus(
  count: number,
  thresholds: Threshold[],
): { total: number; reached: Threshold[] } {
  const reached = thresholds.filter((t) => count >= t.atLeast);
  return { total: reached.reduce((s, t) => s + t.bonus, 0), reached };
}

/** Höchste Einsatz-Stufe für die gespielten Minuten. */
function appearance(minutes: number): { points: number; label: string } | null {
  for (const tier of cfg.appearance) {
    if (minutes >= tier.atLeastMinutes) return { points: tier.points, label: tier.label };
  }
  return null;
}

/** Rating-Bonus-Stufe (oder 0-Punkte-Stufe). */
function ratingTier(rating: number): number {
  for (const t of cfg.ratingBonus.tiers) if (rating >= t.atLeast) return t.points;
  return 0;
}

/**
 * Punkte eines Spielers für ein Spiel.
 * @returns total + breakdown[] (label, count, pointsEach, subtotal) für die UI.
 */
export function calculateScore(
  _player: Player,
  events: PlayerEvents,
  position: Position,
  isCaptain = false,
): ScoreResult {
  const lines: BreakdownLine[] = [];
  const push = (label: string, count: number, pointsEach: number) => {
    if (count === 0 || pointsEach === 0) return;
    lines.push({ label, count, pointsEach, subtotal: round(count * pointsEach) });
  };

  // Einsatz
  const app = appearance(events.minutes);
  if (app) lines.push({ label: app.label, count: 1, pointsEach: app.points, subtotal: app.points });

  // Offensive
  const goalsNonPen = Math.max(0, events.goals - events.penaltyGoals);
  push(cfg.offense.goal.label, goalsNonPen, cfg.offense.goal.points);
  push(cfg.offense.penaltyGoal.label, events.penaltyGoals, cfg.offense.penaltyGoal.points);
  push(cfg.offense.assist.label, events.assists, cfg.offense.assist.points);
  push(cfg.offense.bigChanceCreated.label, events.bigChancesCreated, cfg.offense.bigChanceCreated.points);
  const keyPassesNet = Math.max(0, events.keyPasses - events.bigChancesCreated);
  push(cfg.offense.keyPass.label, keyPassesNet, cfg.offense.keyPass.points);
  push(cfg.offense.shotOnTarget.label, events.shotsOnTarget, cfg.offense.shotOnTarget.points);
  push(cfg.offense.successfulDribble.label, events.successfulDribbles, cfg.offense.successfulDribble.points);

  // Defensive
  const csPts = cfg.cleanSheet.points[position];
  if (csPts > 0 && events.minutes >= cfg.cleanSheet.minMinutes && events.goalsConceded === 0) {
    lines.push({ label: cfg.cleanSheet.label, count: 1, pointsEach: csPts, subtotal: csPts });
  }
  push(cfg.goalConceded.label, events.goalsConceded, cfg.goalConceded.points[position]);
  push(cfg.goalkeeper.save.label, events.saves, cfg.goalkeeper.save.points);
  push(cfg.goalkeeper.penaltySaved.label, events.penaltiesSaved, cfg.goalkeeper.penaltySaved.points);
  push(cfg.defensiveActions.tackleWon.label, events.tacklesWon, cfg.defensiveActions.tackleWon.points[position]);
  push(cfg.defensiveActions.interception.label, events.interceptions, cfg.defensiveActions.interception.points[position]);
  push(cfg.defensiveActions.clearance.label, events.clearances, cfg.defensiveActions.clearance.points[position]);
  push(cfg.defensiveActions.blockedShot.label, events.blockedShots, cfg.defensiveActions.blockedShot.points[position]);

  // Meilensteine (separate Funktion, Schwellen aus Config)
  if (cfg.milestones.saves.positions.includes(position)) {
    for (const r of milestoneBonus(events.saves, cfg.milestones.saves.thresholds).reached) {
      lines.push({ label: `${cfg.milestones.saves.label} (≥${r.atLeast})`, count: 1, pointsEach: r.bonus, subtotal: r.bonus });
    }
  }
  const defComponents = cfg.milestones.defensiveActions.components as (keyof PlayerEvents)[];
  const defCount = defComponents.reduce((s, k) => s + (events[k] as number), 0);
  const defThresholds = cfg.milestones.defensiveActions.byPosition[position];
  for (const r of milestoneBonus(defCount, defThresholds).reached) {
    lines.push({ label: `${cfg.milestones.defensiveActions.label} (≥${r.atLeast})`, count: 1, pointsEach: r.bonus, subtotal: r.bonus });
  }

  // Negativ
  push(cfg.negative.yellowCard.label, events.yellowCards, cfg.negative.yellowCard.points);
  push(cfg.negative.secondYellow.label, events.secondYellowCards, cfg.negative.secondYellow.points);
  push(cfg.negative.redCard.label, events.redCards, cfg.negative.redCard.points);
  push(cfg.negative.ownGoal.label, events.ownGoals, cfg.negative.ownGoal.points);
  push(cfg.negative.penaltyMissed.label, events.penaltiesMissed, cfg.negative.penaltyMissed.points);
  push(cfg.negative.errorLeadToGoal.label, events.errorsLeadToGoal, cfg.negative.errorLeadToGoal.points);
  push(cfg.negative.bigChanceMissed.label, events.bigChancesMissed, cfg.negative.bigChanceMissed.points);
  push(cfg.negative.offside.label, events.offsides, cfg.negative.offside.points);
  push(cfg.negative.foul.label, events.fouls, cfg.negative.foul.points);
  push(cfg.negative.possessionLost.label, events.possessionLost, cfg.negative.possessionLost.points);

  // Rating-Bonus
  if (events.rating != null) {
    const rp = ratingTier(events.rating);
    if (rp !== 0) {
      lines.push({ label: `${cfg.ratingBonus.label} (${events.rating.toFixed(1)})`, count: 1, pointsEach: rp, subtotal: rp });
    }
  }

  let total = round(lines.reduce((s, l) => s + l.subtotal, 0));

  // Kapitän-Multiplikator (aktuell deaktiviert; config-gesteuert).
  if (isCaptain && cfg.captain.enabled && cfg.captain.multiplier !== 1) {
    lines.push({ label: cfg.captain.label, count: 1, pointsEach: total, subtotal: round(total * (cfg.captain.multiplier - 1)) });
    total = round(total * cfg.captain.multiplier);
  }

  return { total, breakdown: lines };
}

export { cfg as scoringConfig };
