// Bepunktet beide Kader eines Sportmonks-Fixtures mit dem aktuellen Scoring und
// schreibt eine HTML-Visualisierung nach /tmp/fixture_score.html.
// Aufruf:  npm run score-fixture -- <fixtureId>

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { calculateScore } from './scoring.js';
import { mapSportmonksStats, SportmonksStat } from './mapping.js';
import { Position, ScoreResult } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
function token(): string {
  if (process.env.SPORTMONKS_API_KEY) return process.env.SPORTMONKS_API_KEY;
  const env = readFileSync(join(__dirname, '../../supabase/.env.local'), 'utf8');
  return env.match(/^SPORTMONKS_API_KEY=(.+)$/m)![1].trim();
}
const TOKEN = token();
const POS: Record<number, Position> = { 24: 'GK', 25: 'DEF', 26: 'MID', 27: 'FWD' };
const POS_DE: Record<Position, string> = { GK: 'TW', DEF: 'ABW', MID: 'MIT', FWD: 'ANG' };

async function sm(path: string) {
  const r = await fetch(`https://api.sportmonks.com/v3/football${path}`, {
    headers: { Authorization: TOKEN, 'User-Agent': 'Mozilla/5.0' },
  });
  if (!r.ok) throw new Error(`Sportmonks ${r.status}`);
  return r.json();
}

interface Row { name: string; pos: Position; minutes: number; res: ScoreResult; }

async function main() {
  const fixtureId = process.argv[2] ?? '19433774';
  const d = (await sm(
    `/fixtures/${fixtureId}?include=participants;lineups.player;lineups.details.type`,
  )).data;

  const teams: Record<number, string> = {};
  for (const p of d.participants ?? []) teams[p.id] = p.name;
  const teamIds = Object.keys(teams).map(Number);

  const byTeam: Record<number, Row[]> = {};
  for (const lu of d.lineups ?? []) {
    const pos = POS[lu.position_id];
    if (!pos) continue;
    const stats: SportmonksStat[] = (lu.details ?? [])
      .map((det: any) => ({ code: det.type?.code, value: Number(det.data?.value ?? det.value ?? 0) }))
      .filter((s: SportmonksStat) => s.code);
    const ev = mapSportmonksStats(stats);
    if (ev.minutes <= 0) continue;
    const res = calculateScore({ id: String(lu.player_id) }, ev, pos, false);
    (byTeam[lu.team_id] ??= []).push({
      name: lu.player?.display_name ?? lu.player?.name ?? String(lu.player_id),
      pos, minutes: ev.minutes, res,
    });
  }
  for (const t of teamIds) (byTeam[t] ??= []).sort((a, b) => b.res.total - a.res.total);

  // ---- Konsole ----
  for (const t of teamIds) {
    console.log(`\n${teams[t]}  (Summe ${byTeam[t].reduce((s, r) => s + r.res.total, 0).toFixed(1)})`);
    for (const r of byTeam[t]) {
      console.log(`  ${r.res.total.toFixed(2).padStart(7)}  ${POS_DE[r.pos]}  ${r.name} (${r.minutes}')`);
    }
  }

  // ---- HTML ----
  const col = (t: number) => {
    const sum = byTeam[t].reduce((s, r) => s + r.res.total, 0);
    const rows = byTeam[t].map((r) => {
      const top = r.res.breakdown
        .filter((b) => b.subtotal !== 0)
        .sort((a, b) => Math.abs(b.subtotal) - Math.abs(a.subtotal))
        .slice(0, 5)
        .map((b) => `${b.label} ${b.subtotal > 0 ? '+' : ''}${b.subtotal}`)
        .join(' · ');
      const cls = r.res.total >= 0 ? 'pos' : 'neg';
      return `<tr><td class="pt ${cls}">${r.res.total.toFixed(1)}</td>
        <td><span class="pos-badge">${POS_DE[r.pos]}</span> <b>${r.name}</b>
        <span class="min">${r.minutes}'</span><div class="bd">${top}</div></td></tr>`;
    }).join('');
    return `<div class="team"><h2>${teams[t]}</h2>
      <div class="sum">Kader-Summe: <b>${sum.toFixed(1)}</b></div>
      <table>${rows}</table></div>`;
  };

  const html = `<!doctype html><html lang="de"><head><meta charset="utf-8">
<style>
  body{margin:0;background:#12141C;color:#EDEFF4;font:15px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;padding:22px}
  h1{font-size:20px;margin:0 0 2px}h1 .up{color:#4ADE6A}
  .sub{color:#A6ACBA;font-size:13px;margin-bottom:18px}
  .cols{display:flex;gap:18px;align-items:flex-start}
  .team{flex:1;background:#1A1D27;border-radius:14px;padding:14px 12px}
  .team h2{font-size:16px;margin:0 0 2px}
  .sum{color:#A6ACBA;font-size:13px;margin-bottom:8px}
  table{width:100%;border-collapse:collapse}
  td{padding:7px 4px;border-top:1px solid #2A2E3A;vertical-align:top}
  .pt{width:44px;font-weight:800;text-align:right;padding-right:10px;font-variant-numeric:tabular-nums}
  .pos{color:#4ADE6A}.neg{color:#F23030}
  .pos-badge{display:inline-block;background:#252937;color:#A6ACBA;border-radius:6px;padding:1px 5px;font-size:11px;font-weight:700;margin-right:4px}
  .min{color:#A6ACBA;font-size:12px;margin-left:4px}
  .bd{color:#8b90a0;font-size:11px;margin-top:2px}
</style></head><body>
  <h1>Match<span class="up">Up</span> · Bepunktung — 34. Spieltag</h1>
  <div class="sub">${d.name} · ${String(d.starting_at).slice(0, 10)} · Voll-Advanced-Scoring (ohne Kapitän, TW entschärft)</div>
  <div class="cols">${teamIds.map(col).join('')}</div>
</body></html>`;
  writeFileSync('/tmp/fixture_score.html', html);
  console.log('\n→ HTML: /tmp/fixture_score.html');
}
main().catch((e) => { console.error(e); process.exit(1); });
