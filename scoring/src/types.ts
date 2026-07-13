// Interne Typen des Scoring-Moduls. Bewusst frei von Sportmonks-Feldnamen —
// die Übersetzung passiert ausschließlich im Mapping-Layer (mapping.ts).

export type Position = 'GK' | 'DEF' | 'MID' | 'FWD';

/** Normalisierte Spieler-Aktionen eines Spiels (Zählwerte + Rating). */
export interface PlayerEvents {
  minutes: number;
  goals: number;            // Tore gesamt (inkl. Elfmeter)
  penaltyGoals: number;     // davon per Elfmeter verwandelt
  assists: number;
  bigChancesCreated: number;
  keyPasses: number;        // gesamt (inkl. der zu Großchancen führenden)
  shotsOnTarget: number;
  successfulDribbles: number;
  goalsConceded: number;    // Gegentore während der eigenen Einsatzzeit
  saves: number;
  penaltiesSaved: number;
  tacklesWon: number;
  interceptions: number;
  clearances: number;
  blockedShots: number;
  yellowCards: number;
  secondYellowCards: number; // Gelb-Rot
  redCards: number;          // glatt Rot
  ownGoals: number;
  penaltiesMissed: number;
  errorsLeadToGoal: number;
  bigChancesMissed: number;
  offsides: number;
  fouls: number;
  possessionLost: number;    // Ballverluste
  rating: number | null;     // Sportmonks 0–10, null = keine Wertung
}

export interface Player {
  id: string;
  name?: string;
}

/** Eine Zeile der Punkte-Aufschlüsselung (für die UI-Anzeige). */
export interface BreakdownLine {
  label: string;
  count: number;
  pointsEach: number;
  subtotal: number;
}

export interface ScoreResult {
  total: number;
  breakdown: BreakdownLine[];
}

/** Leeres Event-Objekt (alle Zähler 0). */
export function emptyEvents(): PlayerEvents {
  return {
    minutes: 0, goals: 0, penaltyGoals: 0, assists: 0, bigChancesCreated: 0,
    keyPasses: 0, shotsOnTarget: 0, successfulDribbles: 0, goalsConceded: 0,
    saves: 0, penaltiesSaved: 0, tacklesWon: 0, interceptions: 0, clearances: 0,
    blockedShots: 0, yellowCards: 0, secondYellowCards: 0, redCards: 0,
    ownGoals: 0, penaltiesMissed: 0, errorsLeadToGoal: 0, bigChancesMissed: 0,
    offsides: 0, fouls: 0, possessionLost: 0, rating: null,
  };
}
