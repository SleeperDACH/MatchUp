// Bundesliga-Transfers (Done Deals) aus Sportmonks. Deckt 1. und 2. Bundesliga
// ab (keine weiteren Ligen): iteriert deren Teams, normalisiert die Deals
// (Spieler, von→zu, Ablöse, Typ, Richtung Zugang/Abgang) und markiert je Seite
// die Liga (division 1 oder 2). Ergebnis wird in transfers_cache gecached.
// Clients rufen nur diese Function; der SPORTMONKS_API_KEY bleibt serverseitig.
//
// Aufruf: POST /functions/v1/transfers  (Body optional)

import { createClient } from "npm:@supabase/supabase-js@2";

// Sportmonks-Team-IDs der 18 Bundesliga-Vereine (Saison 2026/27).
const BL_TEAMS: Record<number, string> = {
  3320: "1. FC Köln",
  1079: "1. FC Union Berlin",
  794: "1. FSV Mainz 05",
  3321: "Bayer 04 Leverkusen",
  68: "Borussia Dortmund",
  683: "Borussia Mönchengladbach",
  366: "Eintracht Frankfurt",
  90: "FC Augsburg",
  503: "FC Bayern München",
  67: "FC Schalke 04",
  2708: "Hamburger SV",
  277: "RB Leipzig",
  3543: "SC Freiburg",
  2642: "SC Paderborn 07",
  3588: "SV 07 Elversberg",
  82: "SV Werder Bremen",
  2726: "TSG Hoffenheim",
  3319: "VfB Stuttgart",
};

// Sportmonks-Liga-IDs (konsistent zu sync-fixtures): 82 = Bundesliga,
// 85 = 2. Bundesliga. Weitere Ligen bleiben bewusst außen vor.
const SM_LEAGUE_BL1 = "82";
const SM_LEAGUE_BL2 = "85";

const ttlMin = Number(Deno.env.get("TRANSFERS_CACHE_TTL_MIN") ?? "720"); // 12h
const MAX_AGE_DAYS = 120; // nur jüngere Deals
// Cache-Schlüssel mit Versionssuffix — beim Schema-Wechsel (division-Feld)
// sorgt das für einen frischen Abruf statt veralteter Payload.
const CACHE_KEY = "bundesliga_v3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sm(path: string, key: string) {
  const res = await fetch(`https://api.sportmonks.com/v3/football${path}`, {
    headers: {
      "Authorization": key,
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
      "Accept": "application/json",
    },
  });
  if (!res.ok) throw new Error(`Sportmonks ${res.status}`);
  return res.json();
}

// Aktuelle Team-IDs einer Liga (über die laufende Saison) — für die dynamische
// 2.-Bundesliga-Abdeckung.
async function seasonTeamIds(leagueKey: string, key: string): Promise<number[]> {
  const l = await sm(`/leagues/${leagueKey}?include=currentSeason`, key);
  const cs = l?.data?.currentseason ?? l?.data?.current_season;
  if (!cs?.id) throw new Error(`Keine aktuelle Saison für Liga ${leagueKey}`);
  const t = await sm(`/teams/seasons/${cs.id}`, key);
  return (t.data ?? [])
    .map((x: Record<string, unknown>) => x.id)
    .filter((x: unknown): x is number => typeof x === "number");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: cached } = await supabase
    .from("transfers_cache")
    .select("fetched_at, payload")
    .eq("key", CACHE_KEY)
    .maybeSingle();
  if (cached) {
    const ageMin = (Date.now() - new Date(cached.fetched_at).getTime()) / 60000;
    if (ageMin < ttlMin) return json(cached.payload);
  }

  const key = Deno.env.get("SPORTMONKS_API_KEY");
  if (!key) {
    if (cached) return json(cached.payload);
    return json({ error: "SPORTMONKS_API_KEY nicht gesetzt." }, 500);
  }

  // Liga-Zuordnung je Team-ID (1 = Bundesliga, 2 = 2. Bundesliga), dynamisch
  // über die laufende Saison — so wandern auf-/absteigende Vereine korrekt mit.
  // Die hartkodierte Liste dient nur als Fallback, falls der 1.-Liga-Abruf
  // ausfällt (2. Liga bleibt dann leer, aber die 1. Liga funktioniert).
  const teamDivision = new Map<number, number>();
  try {
    for (const id of await seasonTeamIds(SM_LEAGUE_BL1, key)) {
      teamDivision.set(id, 1);
    }
  } catch (e) {
    console.error("1. Bundesliga dynamisch fehlgeschlagen, nutze Fallback:", e);
    for (const id of Object.keys(BL_TEAMS)) teamDivision.set(Number(id), 1);
  }
  try {
    for (const id of await seasonTeamIds(SM_LEAGUE_BL2, key)) {
      if (!teamDivision.has(id)) teamDivision.set(id, 2);
    }
  } catch (e) {
    console.error("2. Bundesliga Teams konnten nicht geladen werden:", e);
  }

  const cutoff = Date.now() - MAX_AGE_DAYS * 86400000;
  const byId = new Map<number, Record<string, unknown>>();
  try {
    for (const teamId of teamDivision.keys()) {
      const d = await sm(
        `/transfers/teams/${teamId}?include=player;fromteam;toteam;type&per_page=50`,
        key,
      );
      for (const t of (d.data ?? [])) {
        if (byId.has(t.id)) continue;
        if (t.completed === false) continue;
        const dateMs = t.date ? Date.parse(t.date) : 0;
        if (!dateMs || dateMs < cutoff) continue;
        const from = t.fromteam ?? {};
        const to = t.toteam ?? {};
        const fromDiv = from.id != null ? teamDivision.get(from.id) ?? null : null;
        const toDiv = to.id != null ? teamDivision.get(to.id) ?? null : null;
        const fromBl = fromDiv != null;
        const toBl = toDiv != null;
        if (!fromBl && !toBl) continue; // nur 1./2.-Bundesliga-relevante Deals
        const player = t.player ?? {};
        byId.set(t.id, {
          player: player.display_name ?? player.name ?? "?",
          from_team: from.name ?? "—",
          to_team: to.name ?? "—",
          from_logo: from.image_path ?? null,
          to_logo: to.image_path ?? null,
          from_bundesliga: fromBl,
          to_bundesliga: toBl,
          from_division: fromDiv,
          to_division: toDiv,
          date: t.date ?? null,
          amount: typeof t.amount === "number" ? t.amount : null,
          type: (t.type ?? {}).name ?? null,
        });
      }
    }
  } catch (e) {
    if (cached) return json(cached.payload);
    return json({ error: `Transfer-Abruf fehlgeschlagen: ${e}` }, 502);
  }

  const items = [...byId.values()].sort((a, b) =>
    String(b.date).localeCompare(String(a.date))
  );

  await supabase.from("transfers_cache").upsert({
    key: CACHE_KEY,
    fetched_at: new Date().toISOString(),
    payload: items,
  });
  return json(items);
});
