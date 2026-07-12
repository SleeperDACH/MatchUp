// Bundesliga-Transfers (Done Deals) aus Sportmonks. Iteriert die 18
// Bundesliga-Teams, normalisiert die Deals (Spieler, von→zu, Ablöse, Typ,
// Richtung Zugang/Abgang) und cached sie in transfers_cache. Clients rufen nur
// diese Function; der SPORTMONKS_API_KEY bleibt serverseitig.
//
// Aufruf: POST /functions/v1/transfers  (Body optional)

import { createClient } from "npm:@supabase/supabase-js@2";

// Sportmonks-Team-IDs der 18 Bundesliga-Vereine (Herren).
const BL_TEAMS: Record<number, string> = {
  2831: "1. FC Heidenheim 1846",
  3320: "1. FC Köln",
  1079: "1. FC Union Berlin",
  794: "1. FSV Mainz 05",
  3321: "Bayer 04 Leverkusen",
  68: "Borussia Dortmund",
  683: "Borussia Mönchengladbach",
  366: "Eintracht Frankfurt",
  90: "FC Augsburg",
  503: "FC Bayern München",
  353: "FC St. Pauli",
  2708: "Hamburger SV",
  277: "RB Leipzig",
  3543: "SC Freiburg",
  82: "SV Werder Bremen",
  2726: "TSG Hoffenheim",
  3319: "VfB Stuttgart",
  510: "VfL Wolfsburg",
};

const ttlMin = Number(Deno.env.get("TRANSFERS_CACHE_TTL_MIN") ?? "720"); // 12h
const MAX_AGE_DAYS = 120; // nur jüngere Deals

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
    .eq("key", "bundesliga")
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

  const cutoff = Date.now() - MAX_AGE_DAYS * 86400000;
  const byId = new Map<number, Record<string, unknown>>();
  try {
    for (const teamId of Object.keys(BL_TEAMS)) {
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
        const fromBl = from.id != null && BL_TEAMS[from.id] != null;
        const toBl = to.id != null && BL_TEAMS[to.id] != null;
        if (!fromBl && !toBl) continue; // nur Bundesliga-relevante Deals
        const player = t.player ?? {};
        byId.set(t.id, {
          player: player.display_name ?? player.name ?? "?",
          from_team: from.name ?? "—",
          to_team: to.name ?? "—",
          from_bundesliga: fromBl,
          to_bundesliga: toBl,
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
    key: "bundesliga",
    fetched_at: new Date().toISOString(),
    payload: items,
  });
  return json(items);
});
