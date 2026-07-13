// Mapping-Layer: übersetzt Sportmonks-Statistik-Codes in interne Event-Namen.
// NUR hier dürfen Sportmonks-Feldnamen vorkommen — das Scoring (scoring.ts)
// arbeitet ausschließlich mit den internen PlayerEvents-Feldern.

import { PlayerEvents, emptyEvents } from './types';

/** Eine flache Sportmonks-Statistik: type-Code + Zahlwert. */
export interface SportmonksStat {
  code: string;
  value: number;
}

/**
 * Sportmonks-`type.code` -> internes PlayerEvents-Feld. Mehrere Codes können
 * auf dasselbe Feld zeigen (z. B. Torwart-Gegentore).
 */
export const STAT_CODE_MAP: Record<string, keyof PlayerEvents> = {
  'minutes-played': 'minutes',
  'goals': 'goals',
  'assists': 'assists',
  'big-chances-created': 'bigChancesCreated',
  'big-chances-missed': 'bigChancesMissed',
  'key-passes': 'keyPasses',
  'shots-on-target': 'shotsOnTarget',
  'successful-dribbles': 'successfulDribbles',
  'goals-conceded': 'goalsConceded',
  'goalkeeper-goals-conceded': 'goalsConceded',
  'saves': 'saves',
  'tackles-won': 'tacklesWon',
  'interceptions': 'interceptions',
  'clearances': 'clearances',
  'blocked-shots': 'blockedShots',
  'yellowcards': 'yellowCards',
  'redcards': 'redCards',
  'fouls': 'fouls',
  'offsides': 'offsides',
  'dispossessed': 'possessionLost',
  'error-lead-to-goal': 'errorsLeadToGoal',
  'rating': 'rating',
};

/**
 * Baut aus den Sportmonks-Statistiken eines Spielers das interne Event-Objekt.
 * [extra] fügt Werte hinzu, die nicht in den Lineup-Details stehen, sondern aus
 * Fixture-Events kommen (Elfmeter-Tore/-Fehlschüsse, gehaltene Elfmeter,
 * Eigentore, Gelb-Rot) — so bleibt die Übersetzung an einer Stelle isoliert.
 */
export function mapSportmonksStats(
  stats: SportmonksStat[],
  extra: Partial<PlayerEvents> = {},
): PlayerEvents {
  const ev = emptyEvents();
  for (const s of stats) {
    const field = STAT_CODE_MAP[s.code];
    if (!field) continue;
    if (field === 'rating') {
      ev.rating = s.value;
    } else {
      (ev[field] as number) += s.value;
    }
  }
  return { ...ev, ...extra };
}
