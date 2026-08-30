// Ausfaelle: spiegelt Verletzungen und Sperren nach public.player_absences.
//
// Quelle ist `include=sidelined` — im gebuchten Plan enthalten und bis dahin
// ungenutzt. Gemessen ueber die ganze Liga: 18 von 18 Vereinen liefern, 98
// offene Eintraege (94 Verletzungen, 4 Sperren), davon 79 Spieler in unserem
// Pool. Zuordnung ueber `sportmonks:<id>` = players.id.
//
// **Ein Request fuer die ganze Liga**: `/teams/seasons/<id>?include=sidelined`
// gibt alle 18 Vereine samt Ausfallliste zurueck. Die Saison-ID kommt aus der
// Liga selbst, damit hier keine Zahl steht, die zum Saisonwechsel still
// falsch wird.
//
// Aufruf (Cron oder manuell):
//   POST /functions/v1/sync-absences
//
// Ohne JWT erreichbar (--no-verify-jwt), verlangt Header `x-sync-secret`.

import { createClient } from "npm:@supabase/supabase-js@2";

const BASE = "https://api.sportmonks.com/v3";
// Sportmonks-WAF blockt ohne Browser-User-Agent mit 403.
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120 Safari/537.36";
const KEY = Deno.env.get("SPORTMONKS_API_KEY");

// Bundesliga. Fantasy laeuft bewusst nur auf ihr (entschieden Juli 2026).
const LIGA_ID = 82;

async function smGet(pfad: string): Promise<any> {
  const sep = pfad.includes("?") ? "&" : "?";
  const res = await fetch(`${BASE}${pfad}${sep}api_token=${KEY}`, {
    headers: { "User-Agent": UA, Accept: "application/json" },
  });
  if (res.status === 429) throw new Error("Sportmonks-Ratelimit (HTTP 429)");
  if (!res.ok) throw new Error(`Sportmonks HTTP ${res.status} für ${pfad}`);
  return await res.json();
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }
  if (!KEY) {
    return new Response("SPORTMONKS_API_KEY nicht gesetzt.", { status: 500 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let requests = 0;

  // 1) Laufende Saison der Liga.
  const liga = await smGet(
    `/football/leagues/${LIGA_ID}?include=currentSeason`,
  );
  requests += 1;
  const saisonId = liga?.data?.currentseason?.id;
  if (!saisonId) {
    return Response.json({ error: "Keine laufende Saison gefunden" }, {
      status: 500,
    });
  }

  // 2) Alle Vereine der Saison samt Ausfallliste — ein Request.
  const teams = await smGet(
    `/football/teams/seasons/${saisonId}?include=sidelined`,
  );
  requests += 1;

  type Zeile = {
    id: number;
    player_id: string;
    kategorie: string;
    type_id: number | null;
    seit: string | null;
    bis: string | null;
    spiele_verpasst: number | null;
    updated_at: string;
  };

  const zeilen: Zeile[] = [];
  const typIds = new Set<number>();
  const jetzt = new Date().toISOString();

  for (const t of teams?.data ?? []) {
    for (const e of t.sidelined ?? []) {
      // **Abgeschlossene Ausfaelle sind keine.** `completed` heisst, der
      // Spieler ist wieder da; solche Zeilen gehoeren nicht in eine Liste,
      // die „faellt aus" bedeutet.
      if (e.completed) continue;
      if (e.player_id == null) continue;
      zeilen.push({
        id: e.id,
        player_id: `sportmonks:${e.player_id}`,
        kategorie: e.category === "suspended" ? "suspended" : "injury",
        type_id: e.type_id ?? null,
        seit: e.start_date ?? null,
        bis: e.end_date ?? null,
        spiele_verpasst: e.games_missed ?? null,
        updated_at: jetzt,
      });
      if (e.type_id != null) typIds.add(e.type_id);
    }
  }

  // 3) Nur Spieler, die unser Pool kennt — der Rest ist fuer Fantasy
  //    bedeutungslos und wuerde am Fremdschluessel scheitern.
  const { data: pool } = await supabase.from("players").select("id");
  const bekannt = new Set((pool ?? []).map((p: { id: string }) => p.id));
  const gefiltert = zeilen.filter((z) => bekannt.has(z.player_id));

  // 4) Klartext zu neuen Typ-IDs holen. Es gibt keinen Sammelabruf, nur
  //    `/core/types/<id>` — deshalb die Tabelle, die das Ergebnis behaelt.
  const { data: bekannteTypen } = await supabase
    .from("sideline_types")
    .select("id");
  const schonDa = new Set((bekannteTypen ?? []).map((t: { id: number }) => t.id));
  const neueTypen: { id: number; name: string }[] = [];
  for (const id of typIds) {
    if (schonDa.has(id)) continue;
    try {
      const t = await smGet(`/core/types/${id}`);
      requests += 1;
      const name = t?.data?.name;
      if (typeof name === "string") neueTypen.push({ id, name });
    } catch (_) {
      // Ein fehlender Klartext ist kein Grund, den ganzen Lauf abzubrechen —
      // die Anzeige faellt dann auf die Kategorie zurueck.
    }
  }
  if (neueTypen.length > 0) {
    await supabase.from("sideline_types").upsert(neueTypen, {
      onConflict: "id",
    });
  }

  // 5) Schreiben und Aufraeumen. **Erst upserten, dann loeschen**, damit
  //    zwischen beiden Schritten nie eine leere Liste steht.
  if (gefiltert.length > 0) {
    const { error } = await supabase
      .from("player_absences")
      .upsert(gefiltert, { onConflict: "id" });
    if (error) {
      return Response.json({ error: error.message }, { status: 500 });
    }
  }
  const behalten = gefiltert.map((z) => z.id);
  const del = behalten.length > 0
    ? await supabase.from("player_absences").delete().not(
      "id",
      "in",
      `(${behalten.join(",")})`,
    )
    : await supabase.from("player_absences").delete().gte("id", 0);
  if (del.error) {
    return Response.json({ error: del.error.message }, { status: 500 });
  }

  return Response.json({
    gefunden: zeilen.length,
    imPool: gefiltert.length,
    verletzt: gefiltert.filter((z) => z.kategorie === "injury").length,
    gesperrt: gefiltert.filter((z) => z.kategorie === "suspended").length,
    neueTypen: neueTypen.length,
    requests,
  });
});
