// Kader-Sync: hält den Fantasy-Spielerpool (public.players) automatisch aktuell.
// Holt die kompletten Kader der 18 Bundesliga-Vereine von Sportmonks, spielt
// aktuelle Zugänge per Upsert ein und nimmt abgewanderte Spieler aus dem Pool
// (SQL-Funktion public.fantasy_prune_departed_players, Migration 0117): Sie
// werden markiert (players.abgang_am), aus den Kadern genommen und dort
// gelöscht, wo kein Fremdschlüssel daran hängt.
//
// Portiert die Logik aus tools/import_sportmonks_pool.py (Vereins-Mapping,
// Positionen) in einen serverseitigen, planbaren Lauf — damit Transfers ohne
// manuellen Import und ohne App-Update nachgezogen werden. `club` bleibt 1:1 der
// kanonische OpenLigaDB-Name, sonst bricht das Stats-Matching (sync-stats).
//
// Aufruf (Cron oder manuell):
//   POST /functions/v1/sync-squads
// Ohne JWT erreichbar (--no-verify-jwt), verlangt Header `x-sync-secret`
// (Secret SYNC_SECRET). Braucht zusätzlich das Function-Secret
// SPORTMONKS_API_KEY (bezahlter Plan).

import { createClient } from "npm:@supabase/supabase-js@2";

const BASE = "https://api.sportmonks.com/v3/football";

// Kanonischer OpenLigaDB-Vereinsname -> Sportmonks-Team-ID (Saison 2026/27).
// Muss zum Saisonwechsel (Auf-/Absteiger) aktualisiert werden.
const TEAM_IDS: Record<string, number> = {
  "1. FC Köln": 3320,
  "1. FC Union Berlin": 1079,
  "1. FSV Mainz 05": 794,
  "Bayer 04 Leverkusen": 3321,
  "Borussia Dortmund": 68,
  "Borussia Mönchengladbach": 683,
  "Eintracht Frankfurt": 366,
  "FC Augsburg": 90,
  "FC Bayern München": 503,
  "FC Schalke 04": 67,
  "Hamburger SV": 2708,
  "RB Leipzig": 277,
  "SC Freiburg": 3543,
  "SC Paderborn 07": 2642,
  "SV 07 Elversberg": 3588,
  "SV Werder Bremen": 82,
  "TSG Hoffenheim": 2726,
  "VfB Stuttgart": 3319,
};

// Sportmonks position.developer_name -> App-Position.
const POS: Record<string, string> = {
  GOALKEEPER: "gk",
  DEFENDER: "def",
  MIDFIELDER: "mid",
  ATTACKER: "fwd",
  FORWARD: "fwd",
};

// Sicherheitsschwelle: Ein Kader mit weniger gültigen Spielern gilt als
// verdächtig (API-Problem) — dann wird NICHT geprunt, um keine Spieler wegen
// unvollständiger Daten zu löschen.
const MIN_SQUAD = 15;

// **Hochgezogene Spieler** (26.11.2026, gemeldet an Noah Codjo-Evora: „war
// mit im Bayernkader, fehlt aber in Fantasy"). Sportmonks führt Spieler der
// zweiten Mannschaft oder der U19 nur in deren Kader (`/squads/teams/…` von
// Bayern II), auch wenn sie bei den Profis auf dem Spielberichtsbogen stehen.
// Deshalb zählt zusätzlich jeder, der in den letzten LINEUP_TAGE Tagen in einem
// Spieltagskader (Startelf oder Bank) eines unserer Vereine stand — in
// Bundesliga oder Pokal. Fällt er danach aus dem Fenster und steht in keinem
// Profikader, geht er wie jeder Abgang aus dem Pool.
const LINEUP_TAGE = 42;
const LINEUP_LIGEN = ["bundesliga", "dfb_pokal"];

type Row = {
  id: string;
  name: string;
  position: string;
  club: string;
  birth_date: string;
  nationality: string;
};

// deno-lint-ignore no-explicit-any
async function fetchSquad(teamId: number, token: string): Promise<any[]> {
  const url =
    `${BASE}/squads/teams/${teamId}?include=player.position;player.nationality`;
  let lastErr: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const res = await fetch(url, {
        headers: { Authorization: token, Accept: "application/json" },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      return json.data ?? [];
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 600 * (attempt + 1)));
    }
  }
  throw lastErr;
}

// deno-lint-ignore no-explicit-any
function rowFor(entry: any, club: string): Row | null {
  const p = entry.player ?? {};
  const id = p.id;
  const name = (p.display_name ?? p.name ?? "").trim();
  const dob = p.date_of_birth;
  const pos = POS[(p.position?.developer_name ?? "").toUpperCase()];
  const iso2 = p.nationality?.iso2;
  const nat = typeof iso2 === "string" ? iso2.toLowerCase() : null;
  if (!id || !name || !dob || !pos || !nat) return null;
  // date_of_birth kommt als "YYYY-MM-DD" (ggf. mit Zeit) — nur das Datum.
  const birth = String(dob).slice(0, 10);
  return {
    id: `sportmonks:${id}`,
    name,
    position: pos,
    club,
    birth_date: birth,
    nationality: nat,
  };
}

// Spieltagskader der jüngsten Spiele: bis zu 25 Partien je Request
// (`/fixtures/multi`), Spieler samt Position und Nationalität.
async function lineupRows(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: string,
  clubByTeam: Map<number, string>,
): Promise<{ rows: Row[]; fixtures: number }> {
  const seit = new Date(Date.now() - LINEUP_TAGE * 86400_000).toISOString();
  const { data, error } = await supabase
    .from("fixtures")
    .select("id")
    .in("league_id", LINEUP_LIGEN)
    .gte("kickoff", seit)
    .lte("kickoff", new Date().toISOString());
  if (error) throw new Error(`Fixtures: ${error.message}`);
  const ids = (data ?? [])
    .map((f: { id: string }) => f.id)
    .filter((id: string) => id.startsWith("sportmonks:"))
    .map((id: string) => id.slice("sportmonks:".length));
  const rows: Row[] = [];
  for (let i = 0; i < ids.length; i += 25) {
    const url = `${BASE}/fixtures/multi/${ids.slice(i, i + 25).join(",")}` +
      `?include=lineups.player.position;lineups.player.nationality`;
    const res = await fetch(url, {
      headers: { Authorization: token, Accept: "application/json" },
    });
    if (!res.ok) throw new Error(`Lineups HTTP ${res.status}`);
    const json = await res.json();
    for (const f of json.data ?? []) {
      for (const l of f.lineups ?? []) {
        const club = clubByTeam.get(l.team_id);
        if (!club) continue;
        const row = rowFor(l, club);
        if (row) rows.push(row);
      }
    }
    await new Promise((r) => setTimeout(r, 150));
  }
  return { rows, fixtures: ids.length };
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const token = Deno.env.get("SPORTMONKS_API_KEY");
  if (!token) {
    return new Response(
      "SPORTMONKS_API_KEY fehlt (Function-Secret setzen).",
      { status: 500 },
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const rows: Row[] = [];
  const perClub: Record<string, number> = {};
  let allClubsOk = true;

  for (const [club, teamId] of Object.entries(TEAM_IDS)) {
    let kept = 0;
    try {
      const squad = await fetchSquad(teamId, token);
      for (const e of squad) {
        const row = rowFor(e, club);
        if (row) {
          rows.push(row);
          kept++;
        }
      }
    } catch (e) {
      allClubsOk = false;
      perClub[club] = -1; // Fehler-Marker
      console.error(`Kader-Fehler ${club} (${teamId}): ${e}`);
      continue;
    }
    perClub[club] = kept;
    if (kept < MIN_SQUAD) allClubsOk = false;
    await new Promise((r) => setTimeout(r, 150)); // sanft zur API
  }

  // Hochgezogene Spieler ergänzen. Wer im Profikader steht, behält dessen
  // Zeile (Verein aus dem Kader, nicht aus einem älteren Spiel). Scheitert
  // dieser Teil, wird nicht geprunt — sonst flögen die Hochgezogenen raus.
  const imKader = new Set(rows.map((r) => r.id));
  let hochgezogen: string[] = [];
  let lineupSpiele = 0;
  try {
    const clubByTeam = new Map(
      Object.entries(TEAM_IDS).map(([club, id]) => [id, club]),
    );
    const l = await lineupRows(supabase, token, clubByTeam);
    lineupSpiele = l.fixtures;
    for (const r of l.rows) {
      if (imKader.has(r.id)) continue;
      imKader.add(r.id);
      rows.push(r);
      hochgezogen.push(`${r.name} (${r.club})`);
    }
  } catch (e) {
    allClubsOk = false;
    hochgezogen = [];
    console.error(`Spieltagskader-Fehler: ${e}`);
  }

  // Zugänge/Aktualisierungen einspielen. `is_foreign_newcomer` wird bewusst
  // NICHT mitgeschickt: bei INSERT greift der Default (false), bei UPDATE bleibt
  // der bestehende Wert erhalten (wie im Python-Import).
  let upserted = 0;
  if (rows.length > 0) {
    const { error } = await supabase
      .from("players")
      .upsert(rows, { onConflict: "id" });
    if (error) {
      return new Response(`Upsert-Fehler: ${error.message}`, { status: 500 });
    }
    upserted = rows.length;
  }

  // Abgänge nur entfernen, wenn ALLE Kader plausibel geladen wurden — sonst
  // droht durch API-Lücken ein Massen-Löschen.
  let pruned:
    | { deleted: number; kept: number; abgewandert: number; ausKadern: number }
    | null = null;
  let pruneSkippedReason: string | null = null;
  if (!allClubsOk) {
    pruneSkippedReason =
      "Mindestens ein Kader fehlte/zu klein — Entfernen übersprungen.";
  } else {
    const { data, error } = await supabase.rpc(
      "fantasy_prune_departed_players",
      { p_current_ids: rows.map((r) => r.id), p_bl_clubs: Object.keys(TEAM_IDS) },
    );
    if (error) {
      return new Response(`Prune-Fehler: ${error.message}`, { status: 500 });
    }
    const r = Array.isArray(data) ? data[0] : data;
    pruned = {
      deleted: r?.deleted ?? 0,
      kept: r?.kept ?? 0,
      abgewandert: r?.abgewandert ?? 0,
      ausKadern: r?.aus_kadern ?? 0,
    };
  }

  return new Response(
    JSON.stringify({
      upserted,
      pruned,
      pruneSkippedReason,
      perClub,
      lineupSpiele,
      hochgezogen,
    }),
    { headers: { "content-type": "application/json" } },
  );
});
