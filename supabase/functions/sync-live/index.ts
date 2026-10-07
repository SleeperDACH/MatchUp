// Live-Abgleich für Push: Anpfiff, Tore, Rote Karten, Halbzeit und Abpfiff
// in den Spielen der Lieblingsvereine.
//
// Die Function stellt nichts selbst fest. Sie holt je Minute die Spiele, die
// gerade laufen oder gleich beginnen, und reicht je Spiel einen Schnappschuss
// an `push_live_abgleich` (Migration 0131). Was davon neu ist, entscheidet die
// Datenbank — dort liegen der letzte Stand, die Aufträge und der neue Stand in
// einer Transaktion.
//
// Leerlauf kostet nichts: `push_live_kandidaten` liefert nur Spiele mit
// Anstoß zwischen vier Stunden zurück und fünf Minuten voraus, und nur, wenn
// überhaupt jemand einen Lieblingsverein und ein Gerät hat. Sonst kein
// einziger Sportmonks-Request.
//
// Aufruf (Cron oder manuell):
//   POST /functions/v1/sync-live                  → Abgleich
//   POST /functions/v1/sync-live?probe=<sm-id>    → nur Schnappschuss zeigen,
//                                                   nichts schreiben
//
// Ohne JWT erreichbar (--no-verify-jwt), verlangt Header `x-sync-secret`.

import { createClient } from "npm:@supabase/supabase-js@2";

const BASE = "https://api.sportmonks.com/v3/football";
// Sportmonks-WAF blockt ohne Browser-User-Agent mit 403.
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120 Safari/537.36";
const KEY = Deno.env.get("SPORTMONKS_API_KEY");
const BATCH = 25;

// Ereignis-Typen (event-Kreis, siehe sync-stats und CLAUDE.md — im
// statistic-Kreis bedeuten dieselben Zahlen etwas anderes).
const EV_GOAL = 14;
const EV_OWNGOAL = 15;
const EV_PENALTY_GOAL = 16;
const EV_RED = 20;
const EV_YELLOW_RED = 21;

const ART: Record<number, string> = {
  [EV_GOAL]: "tor",
  [EV_OWNGOAL]: "eigentor",
  [EV_PENALTY_GOAL]: "elfmeter",
  [EV_RED]: "rot",
  [EV_YELLOW_RED]: "gelbrot",
};

// deno-lint-ignore no-explicit-any
async function smGet(path: string): Promise<any> {
  const sep = path.includes("?") ? "&" : "?";
  const res = await fetch(`${BASE}${path}${sep}api_token=${KEY}`, {
    headers: { "User-Agent": UA, Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`Sportmonks HTTP ${res.status} für ${path}`);
  return await res.json();
}

// deno-lint-ignore no-explicit-any
function tore(scores: any[], loc: string): number | null {
  const e = (scores ?? []).find(
    (x) => x.description === "CURRENT" && x?.score?.participant === loc,
  );
  return e ? (e.score?.goals ?? null) : null;
}

/// Sportmonks schreibt den Stand nach dem Tor als „1-0".
function stand(result: unknown): string | null {
  if (typeof result !== "string") return null;
  const m = result.match(/^\s*(\d+)\s*-\s*(\d+)\s*$/);
  return m ? `${m[1]}:${m[2]}` : null;
}

function minute(e: { minute?: number; extra_minute?: number }): string | null {
  if (typeof e.minute !== "number") return null;
  return typeof e.extra_minute === "number" && e.extra_minute > 0
    ? `${e.minute}+${e.extra_minute}`
    : String(e.minute);
}

// deno-lint-ignore no-explicit-any
function schnappschuss(f: any) {
  const parts = f.participants ?? [];
  // deno-lint-ignore no-explicit-any
  const heim = parts.find((p: any) => p?.meta?.location === "home") ?? parts[0];
  // deno-lint-ignore no-explicit-any
  const gast = parts.find((p: any) => p?.meta?.location === "away") ?? parts[1];
  const name = new Map<number, string>();
  for (const p of parts) name.set(p.id, p.name);

  const ereignisse = [];
  for (const e of f.events ?? []) {
    const art = ART[e.type_id as number];
    if (!art || typeof e.id !== "number") continue;
    ereignisse.push({
      id: e.id,
      art,
      minute: minute(e),
      spieler: e.player_name ?? null,
      team: name.get(e.participant_id) ?? null,
      stand: stand(e.result),
    });
  }

  return {
    fixture_id: `sportmonks:${f.id}`,
    zustand: String(f.state?.state ?? "NS").toUpperCase(),
    heim: heim?.name ?? "?",
    gast: gast?.name ?? "?",
    heim_key: heim ? `sportmonks:${heim.id}` : null,
    gast_key: gast ? `sportmonks:${gast.id}` : null,
    tore_heim: heim ? tore(f.scores, "home") : null,
    tore_gast: gast ? tore(f.scores, "away") : null,
    ereignisse,
  };
}

function chunk<T>(xs: T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += n) out.push(xs.slice(i, i + n));
  return out;
}

const INCLUDE = "participants;scores;state;events";

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const url = new URL(req.url);
  const probe = url.searchParams.get("probe");
  if (probe) {
    const r = await smGet(`/fixtures/${probe}?include=${INCLUDE}`);
    return Response.json(r?.data ? schnappschuss(r.data) : null);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: kandidaten, error } = await supabase.rpc(
    "push_live_kandidaten",
  );
  if (error) {
    return Response.json({ fehler: error.message }, { status: 500 });
  }
  const ids = ((kandidaten ?? []) as string[])
    .filter((id) => id.startsWith("sportmonks:"))
    .map((id) => id.slice("sportmonks:".length));
  if (ids.length === 0) return Response.json({ spiele: 0, auftraege: 0 });

  let auftraege = 0;
  let requests = 0;
  const fehler: string[] = [];

  for (const teil of chunk(ids, BATCH)) {
    const r = await smGet(`/fixtures/multi/${teil.join(",")}?include=${INCLUDE}`);
    requests += 1;
    for (const f of r?.data ?? []) {
      const { data: n, error: e } = await supabase.rpc("push_live_abgleich", {
        p: schnappschuss(f),
      });
      if (e) fehler.push(`${f.id}: ${e.message}`);
      else auftraege += (n as number) ?? 0;
    }
  }

  return Response.json(
    { spiele: ids.length, requests, auftraege, fehler },
    { status: fehler.length > 0 ? 500 : 200 },
  );
});
