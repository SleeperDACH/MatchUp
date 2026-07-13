// Simulation: lädt eine komplette Bundesliga-Saison (Sportmonks) und berechnet
// die Punkte NUR der Startelf-Spieler (type_id 11). Gibt die Verteilung je
// Position aus (Mittelwert, Median, P90, P97, Min/Max) + Warnung, wenn der
// Mittelwert-Spread zwischen den Positionen > 5 % ist.
//
// Aufruf:  npm run simulate -- [startDatum] [endDatum]
//   Default: komplette Saison 2025/26 (2025-08-01 … 2026-05-31)

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

const STARTER_TYPE_ID = 11; // Sportmonks: 11 = Startelf, 12 = Bank

async function main() {
  const from = process.argv[2] ?? '2025-08-01';
  const to = process.argv[3] ?? '2026-05-31';

  // Der between-Endpoint begrenzt den Zeitraum → in ~80-Tage-Fenster zerlegen.
  const windows: [string, string][] = [];
  for (let s = new Date(from); s < new Date(to);) {
    const e = new Date(s);
    e.setDate(e.getDate() + 80);
    const end = e > new Date(to) ? new Date(to) : e;
    windows.push([s.toISOString().slice(0, 10), end.toISOString().slice(0, 10)]);
    s = new Date(end);
    s.setDate(s.getDate() + 1);
  }

  const fixtures: any[] = [];
  for (const [ws, we] of windows) {
    let page = 1;
    for (;;) {
      const d = await sm(
        `/fixtures/between/${ws}/${we}?filters=fixtureLeagues:82` +
        `&include=lineups.details.type&per_page=50&page=${page}`,
      );
      fixtures.push(...(d.data ?? []));
      if (!d.pagination?.has_more) break;
      page++;
    }
  }
  const use = fixtures.filter((f) => (f.lineups ?? []).some((l: any) => (l.details ?? []).length));
  const rounds = new Set(use.map((f) => f.round_id));

  const totals: Record<Position, number[]> = { GK: [], DEF: [], MID: [], FWD: [] };
  for (const f of use) {
    for (const lu of f.lineups ?? []) {
      if (lu.type_id !== STARTER_TYPE_ID) continue; // nur Startelf
      const pos = POS[lu.position_id];
      if (!pos) continue;
      const stats: SportmonksStat[] = (lu.details ?? [])
        .map((det: any) => ({
          code: det.type?.code as string,
          value: Number(det.data?.value ?? det.value ?? 0),
        }))
        .filter((s: SportmonksStat) => s.code);
      const events = mapSportmonksStats(stats);
      const { total } = calculateScore({ id: String(lu.player_id) }, events, pos, false);
      totals[pos].push(total);
    }
  }

  console.log(`\nSimulation (nur Startelf): ${use.length} Spiele, ${rounds.size} Spieltag(e) [${from} … ${to}]\n`);
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
