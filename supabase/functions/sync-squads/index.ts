// Kader-Sync: hält den Fantasy-Spielerpool (public.players) automatisch aktuell.
// Holt die kompletten Kader der 18 Bundesliga-Vereine von Sportmonks, spielt
// aktuelle Zugänge per Upsert ein und entfernt abgewanderte Spieler FK-sicher
// (nur wenn sie in keiner Liga gedraftet/gerostert sind — siehe SQL-Funktion
// public.fantasy_prune_departed_players in Migration 0073).
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
  let pruned: { deleted: number; kept: number } | null = null;
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
    pruned = { deleted: r?.deleted ?? 0, kept: r?.kept ?? 0 };
  }

  return new Response(
    JSON.stringify({ upserted, pruned, pruneSkippedReason, perClub }),
    { headers: { "content-type": "application/json" } },
  );
});
