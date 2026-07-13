import { describe, expect, it } from 'vitest';
import { calculateScore, milestoneBonus } from '../src/scoring';
import { emptyEvents, PlayerEvents, Position } from '../src/types';

const P = { id: 'p1', name: 'Test' };
const ev = (partial: Partial<PlayerEvents>): PlayerEvents => ({ ...emptyEvents(), ...partial });
const score = (e: Partial<PlayerEvents>, pos: Position, cap = false) =>
  calculateScore(P, ev(e), pos, cap);
const label = (r: ReturnType<typeof score>, l: string) =>
  r.breakdown.find((b) => b.label.startsWith(l));

describe('milestoneBonus (kumulativ, aus Config)', () => {
  const saves = [{ atLeast: 5, bonus: 4 }, { atLeast: 8, bonus: 6 }];
  it('unter der ersten Schwelle → 0', () => {
    expect(milestoneBonus(4, saves).total).toBe(0);
  });
  it('erste Schwelle → +4', () => {
    expect(milestoneBonus(5, saves).total).toBe(4);
  });
  it('beide Schwellen kumulativ → +10', () => {
    const m = milestoneBonus(8, saves);
    expect(m.total).toBe(10);
    expect(m.reached).toHaveLength(2);
  });
});

describe('Einsatz-Stufen', () => {
  it('exakte Werte je Minuten', () => {
    expect(score({ minutes: 10 }, 'MID').total).toBe(1);
    expect(score({ minutes: 45 }, 'MID').total).toBe(2);
    expect(score({ minutes: 75 }, 'MID').total).toBe(3);
    expect(score({ minutes: 90 }, 'MID').total).toBe(5);
    expect(score({ minutes: 0 }, 'MID').total).toBe(0);
  });
});

describe('Exakte Referenz-Fälle', () => {
  it('MID: 90 Min + 1 Tor = 13', () => {
    expect(score({ minutes: 90, goals: 1 }, 'MID').total).toBe(13);
  });
  it('GK-Durchschnitt: 90 Min, 3 Paraden, 1 GT (−3), Rating 6.8 = 6.5', () => {
    // 5 (Einsatz) + 3×1.5 (Paraden) − 3 (Gegentor) + 0 (Rating) = 6.5
    expect(score({ minutes: 90, saves: 3, goalsConceded: 1, rating: 6.8 }, 'GK').total).toBe(6.5);
  });
  it('FWD: 60 Min + 1 Tor = 11; Kapitän hat keinen Effekt', () => {
    expect(score({ minutes: 60, goals: 1, rating: 6.5 }, 'FWD').total).toBe(11);
    expect(score({ minutes: 60, goals: 1, rating: 6.5 }, 'FWD', true).total).toBe(11);
  });
  it('Elfmeter-Tor zählt 6, normales Tor 8', () => {
    const r = score({ minutes: 90, goals: 2, penaltyGoals: 1 }, 'FWD');
    expect(label(r, 'Tor (Elfmeter)')?.subtotal).toBe(6);
    expect(label(r, 'Tor')?.count).toBe(1); // 1 normales Tor
    expect(r.total).toBe(5 + 8 + 6);
  });
});

// -------------------- GK --------------------
describe('GK', () => {
  it('Monster: viele Paraden, Zu-Null, gehaltener Elfer, Top-Rating', () => {
    const r = score({
      minutes: 90, saves: 8, penaltiesSaved: 1, goalsConceded: 0,
      clearances: 3, rating: 9.2,
    }, 'GK');
    expect(label(r, 'Paraden-Meilenstein')).toBeTruthy();
    expect(label(r, 'Zu Null')?.subtotal).toBe(6);
    expect(label(r, 'Gehaltener Elfmeter')?.subtotal).toBe(6);
    expect(label(r, 'Rating-Bonus')?.subtotal).toBe(5);
    expect(r.total).toBeGreaterThan(35);
  });
  it('Durchschnitt: solide, moderat positiv', () => {
    const r = score({ minutes: 90, saves: 3, goalsConceded: 1, rating: 6.9 }, 'GK');
    expect(r.total).toBeGreaterThan(5);
    expect(r.total).toBeLessThan(15);
  });
  it('Katastrophe: viele Gegentore, Eigentor, Rot, klar negativ', () => {
    const r = score({
      minutes: 90, goalsConceded: 5, ownGoals: 1, redCards: 1,
      errorsLeadToGoal: 1, rating: 3.4,
    }, 'GK');
    expect(r.total).toBeLessThan(0);
  });
});

// -------------------- DEF --------------------
describe('DEF', () => {
  it('Monster: Tor + Zu-Null + Defensiv-Meilenstein + Top-Rating', () => {
    const r = score({
      minutes: 90, goals: 1, goalsConceded: 0,
      tacklesWon: 6, interceptions: 5, clearances: 5, blockedShots: 2, rating: 8.6,
    }, 'DEF');
    expect(label(r, 'Zu Null')?.subtotal).toBe(6);
    expect(label(r, 'Defensiv-Meilenstein')).toBeTruthy();
    expect(r.total).toBeGreaterThan(25);
  });
  it('Durchschnitt: Zu-Null + wenige Aktionen', () => {
    const r = score({
      minutes: 90, goalsConceded: 0, tacklesWon: 2, clearances: 3, rating: 7.0,
    }, 'DEF');
    expect(r.total).toBeGreaterThan(8);
    expect(r.total).toBeLessThan(20);
  });
  it('Katastrophe: Eigentor + Rot + Fehler', () => {
    const r = score({
      minutes: 90, goalsConceded: 3, ownGoals: 1, secondYellowCards: 1,
      yellowCards: 1, errorsLeadToGoal: 1, rating: 4.2,
    }, 'DEF');
    expect(r.total).toBeLessThan(0);
  });
});

// -------------------- MID --------------------
describe('MID', () => {
  it('Monster: Tor + 2 Vorlagen + Großchancen + Top-Rating', () => {
    const r = score({
      minutes: 90, goals: 1, assists: 2, bigChancesCreated: 2, keyPasses: 4,
      shotsOnTarget: 3, successfulDribbles: 4, rating: 9.0,
    }, 'MID');
    expect(label(r, 'Vorlage')?.subtotal).toBe(12);
    expect(label(r, 'Rating-Bonus')?.subtotal).toBe(5);
    expect(r.total).toBeGreaterThan(30);
  });
  it('Durchschnitt: 1 Vorlage, etwas Aufbau', () => {
    const r = score({
      minutes: 90, assists: 1, keyPasses: 2, successfulDribbles: 2, rating: 7.1,
    }, 'MID');
    expect(r.total).toBeGreaterThan(8);
    expect(r.total).toBeLessThan(20);
  });
  it('Katastrophe: verschossener Elfer + Rot + Fehler', () => {
    const r = score({
      minutes: 90, penaltiesMissed: 1, redCards: 1, errorsLeadToGoal: 1,
      bigChancesMissed: 1, rating: 3.8,
    }, 'MID');
    expect(r.total).toBeLessThan(0);
  });
});

// -------------------- FWD --------------------
describe('FWD', () => {
  it('Monster: 2 Tore + Vorlage + Top-Rating', () => {
    const r = score({
      minutes: 90, goals: 2, assists: 1, shotsOnTarget: 4, successfulDribbles: 3, rating: 8.9,
    }, 'FWD');
    expect(label(r, 'Tor')?.subtotal).toBe(16);
    expect(r.total).toBeGreaterThan(30);
  });
  it('Durchschnitt: 1 Tor, moderat', () => {
    const r = score({ minutes: 75, goals: 1, shotsOnTarget: 2, rating: 6.7 }, 'FWD');
    expect(r.total).toBeGreaterThan(8);
    expect(r.total).toBeLessThan(18);
  });
  it('Katastrophe: Großchance vergeben + Elfer verschossen + Rot', () => {
    const r = score({
      minutes: 90, bigChancesMissed: 2, penaltiesMissed: 1, redCards: 1, rating: 4.1,
    }, 'FWD');
    expect(r.total).toBeLessThan(0);
  });
  it('Kapitän hat keinen Effekt (Verdopplung entfernt)', () => {
    const base = score({ minutes: 90, redCards: 1, rating: 4.0 }, 'FWD');
    const cap = score({ minutes: 90, redCards: 1, rating: 4.0 }, 'FWD', true);
    expect(cap.total).toBe(base.total);
  });
});
