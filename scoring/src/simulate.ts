// Simulation: lädt N Bundesliga-Spieltage (Sportmonks), berechnet die Punkte
// je Spieler und gibt die Verteilung je Position aus (Mittelwert, Median, P90,
// P97, Min/Max) + Warnung, wenn der Mittelwert-Spread zwischen den Positionen
// > 5 % ist.
//
// Aufruf:  npm run simulate -- [anzahlSpieltage] [startDatum] [endDatum]
//   z. B.  npm run simulate -- 4 2026-04-01 2026-05-20

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { calculateScore } from './scoring.js';
import { mapSportmonksStats, SportmonksStat } from './mapping.js';
import { Position } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

function token(): string {
  if (process.env.SPORTMONKS_API_KEY) return process.env.SPORTMONKS_API_KEY;
  const env = readFileSync(join(__dirname, '../../supabase/.env.local'), 'utf8');
  const m = env.match(/^SPORTMONKS_API_KEY=(.+)$/m);
  if (!m) throw new Error('SPORTMONKS_API_KEY nicht gefunden.');
  return m[1].trim();
}
const TOKEN = token();

// Sportmonks position_id -> interne Position.
const POS: Record<number, Position> = { 24: 'GK', 25: 'DEF', 26: 'MID', 27: 'FWD' };

async function sm(path: string): Promise<any> {
  const res = await fetch(`https://api.sportmonks.com/v3/football${path}`, {
    headers: { Authorization: TOKEN, 'User-Agent': 'Mozilla/5.0' },
  });
  if (!res.ok) throw new Error(`Sportmonks ${res.status} für ${path}`);
  return res.json();
}

function pct(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const idx = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[idx];
}
const mean = (a: number[]) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0);
function median(a: number[]): number {
  if (!a.length) return 0;
  const s = [...a].sort((x, y) => x - y);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

async function main() {
  const matchdays = Number(process.argv[2] ?? 3);
  const from = process.argv[3] ?? '2026-04-01';
  const to = process.argv[4] ?? '2026-05-20';

  // Fixtures im Zeitfenster (Bundesliga) inkl. Spieler-Statistiken laden.
  let page = 1;
  const fixtures: any[] = [];
  for (;;) {
    const d = await sm(
      `/fixtures/between/${from}/${to}?filters=fixtureLeagues:82` +
      `&include=lineups.details.type&per_page=50&page=${page}`,
    );
    fixtures.push(...(d.data ?? []));
    if (!d.pagination?.has_more) break;
    page++;
  }
  // Nur beendete, nach Spieltag (round_id) sortiert; letzte N Spieltage nehmen.
  const played = fixtures.filter((f) => (f.lineups ?? []).some((l: any) => (l.details ?? []).length));
  const rounds = [...new Set(played.map((f) => f.round_id))].sort((a, b) => a - b);
  const keep = new Set(rounds.slice(-matchdays));
  const use = played.filter((f) => keep.has(f.round_id));

  const totals: Record<Position, number[]> = { GK: [], DEF: [], MID: [], FWD: [] };
  for (const f of use) {
    for (const lu of f.lineups ?? []) {
      const pos = POS[lu.position_id];
      if (!pos) continue;
      const stats: SportmonksStat[] = (lu.details ?? [])
        .map((det: any) => ({
          code: det.type?.code as string,
          value: Number(det.data?.value ?? det.value ?? 0),
        }))
        .filter((s: SportmonksStat) => s.code);
      const events = mapSportmonksStats(stats);
      if (events.minutes <= 0) continue; // nur Einsatzspieler
      const { total } = calculateScore({ id: String(lu.player_id) }, events, pos, false);
      totals[pos].push(total);
    }
  }

  console.log(`\nSimulation: ${use.length} Spiele, ${keep.size} Spieltag(e) [${from} … ${to}]\n`);
  console.log('Pos   n     Mittel  Median   P90    P97    Min    Max');
  const means: number[] = [];
  for (const pos of ['GK', 'DEF', 'MID', 'FWD'] as Position[]) {
    const arr = totals[pos];
    const sorted = [...arr].sort((a, b) => a - b);
    const m = mean(arr);
    means.push(m);
    const f = (n: number) => n.toFixed(1).padStart(6);
    console.log(
      `${pos}   ${String(arr.length).padStart(3)}  ${f(m)}  ${f(median(arr))}  ` +
      `${f(pct(sorted, 90))} ${f(pct(sorted, 97))} ${f(sorted[0] ?? 0)} ${f(sorted[sorted.length - 1] ?? 0)}`,
    );
  }

  const avg = mean(means);
  const spread = avg ? (Math.max(...means) - Math.min(...means)) / avg : 0;
  console.log(`\nMittelwert-Spread zwischen Positionen: ${(spread * 100).toFixed(1)} %`);
  if (spread > 0.05) {
    console.log('⚠️  WARNUNG: Spread > 5 % — Positionen sind unausgewogen, Werte prüfen.');
  } else {
    console.log('✅  Spread ≤ 5 % — Positionen sind ausgewogen.');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
