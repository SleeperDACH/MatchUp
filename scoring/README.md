# MatchUp – Fantasy-Scoring (TypeScript)

Punkte pro Spieler pro Spiel aus Sportmonks-Match-Events. Alle Werte in
`config/scoring.config.json` (keine Magic Numbers im Code). Positionen:
`GK | DEF | MID | FWD`, alle Aktionswerte flat.

## Struktur
- `config/scoring.config.json` – sämtliche Punktwerte, Schwellen, Kapitän-Faktor.
- `src/types.ts` – interne Typen (`PlayerEvents`, `ScoreResult`, …), Sportmonks-frei.
- `src/mapping.ts` – **einziger** Ort mit Sportmonks-Feldnamen (Stat-Code → Event).
- `src/scoring.ts` – `calculateScore(player, events, position, isCaptain)` →
  `{ total, breakdown[] }`; `milestoneBonus(count, thresholds)` separat.
- `src/simulate.ts` – lädt N Spieltage, gibt Verteilung je Position (Mittel,
  Median, P90, P97, Min/Max) + Warnung bei Spread > 5 % aus.
- `test/scoring.test.ts` – Vitest: Monster-/Durchschnitts-/Katastrophen-Spiel
  je Position + Referenz- und Meilenstein-Fälle.

## Nutzung
```sh
npm install
npm test                      # Unit-Tests
npm run simulate -- 4 2026-04-01 2026-05-20   # Balance-Simulation (braucht SPORTMONKS_API_KEY)
```

```ts
import { calculateScore, mapSportmonksStats } from './src';
const events = mapSportmonksStats(sportmonksStats /*, extra */);
const { total, breakdown } = calculateScore({ id }, events, 'MID', false);
```
