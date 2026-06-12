// Wettquoten-Proxy: holt 1X2-Quoten von the-odds-api.com mit dem geheimen
// ODDS_API_KEY und cached sie in public.odds_cache. Clients rufen nur diese
// Function (kein Key im App-Bundle). Eine Abfrage versorgt alle Nutzer und
// schont das Gratis-Limit (~500 Requests/Monat).
//
// Aufruf (vom Client, mit Anon-Key via supabase.functions.invoke):
//   POST /functions/v1/odds   Body: { "sport": "soccer_fifa_world_cup" }
//
// Mapping der erlaubten Sport-Keys = LeagueInfo.oddsSportKey in der App.

import { createClient } from "npm:@supabase/supabase-js@2";

const ALLOWED_SPORTS = new Set([
  "soccer_fifa_world_cup",
  "soccer_germany_bundesliga",
]);

// Quoten ändern sich, aber für die reine Anzeige reicht ein großzügiger
// Cache — hält die API-Nutzung klein. Überschreibbar per Secret.
const ttlMin = Number(Deno.env.get("ODDS_CACHE_TTL_MIN") ?? "360");

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Sport-Key aus Body (bevorzugt) oder Query.
  let sport = new URL(req.url).searchParams.get("sport") ?? "";
  if (!sport && req.method === "POST") {
    try {
      const body = await req.json();
      sport = body?.sport ?? "";
    } catch (_) {
      // kein/ungültiger Body — sport bleibt leer
    }
  }
  if (!ALLOWED_SPORTS.has(sport)) {
    return json({ error: "Unbekannter oder fehlender sport-Key." }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Frischen Cache-Eintrag direkt zurückgeben.
  const { data: cached } = await supabase
    .from("odds_cache")
    .select("fetched_at, payload")
    .eq("sport", sport)
    .maybeSingle();

  if (cached) {
    const ageMin =
      (Date.now() - new Date(cached.fetched_at).getTime()) / 60000;
    if (ageMin < ttlMin) {
      return json(cached.payload);
    }
  }

  // Cache veraltet/leer → frisch holen.
  const apiKey = Deno.env.get("ODDS_API_KEY");
  if (!apiKey) {
    // Kein Key konfiguriert: lieber alten Cache liefern als Fehler.
    if (cached) return json(cached.payload);
    return json({ error: "ODDS_API_KEY nicht gesetzt." }, 500);
  }

  const url =
    `https://api.the-odds-api.com/v4/sports/${sport}/odds/` +
    `?apiKey=${apiKey}&regions=eu&markets=h2h&oddsFormat=decimal`;

  const res = await fetch(url);
  if (!res.ok) {
    // Bei API-Fehler (z. B. Limit erschöpft) den alten Cache weiterreichen.
    if (cached) return json(cached.payload);
    return json({ error: `Quoten-API ${res.status}` }, 502);
  }
  const payload = await res.json();

  await supabase
    .from("odds_cache")
    .upsert({ sport, payload, fetched_at: new Date().toISOString() });

  return json(payload);
});
