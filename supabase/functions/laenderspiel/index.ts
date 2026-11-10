// Länderspiel-Details von API-Football: Aufstellungen, Tore, Karten, Wechsel
// (mit Minute) und Mannschaftsstatistik der deutschen Nationalmannschaft.
//
// **Warum eine zweite Quelle.** Sportmonks führt Länderspiele in unserem Abo
// nicht; OpenLigaDB (Spielplan und Stand, `DFBN`) liefert nur Tore. API-Football
// gibt im Gratis-Tarif (100 Abrufe/Tag) jedes Spiel vollständig heraus — aber
// **nur im Datumsfenster gestern bis morgen** und keine Abfrage nach Liga oder
// Saison (gemessen 09.11.2026: „Free plans do not have access to this season,
// try from 2022 to 2024", nach Datum dagegen 1237 Spiele samt laufender
// Saison). Daraus folgt der Aufbau:
//
//   * Gefragt wird nur nach Datum (gefiltert auf Team 25, Deutschland),
//     dann nach der Spiel-ID. Beides liegt im Fenster, solange jemand am
//     Spieltag hinsieht.
//   * Alles landet in `public.sportmonks_cache` (Schlüssel `af:de:<Datum>`).
//     Ist das Spiel aus, wird der Stand **für immer** gemerkt — nach dem
//     Fenster käme API-Football nicht mehr heran.
//   * Ein Cron (`sammeln`) holt nachts die Endstände der Spiele der letzten
//     30 Stunden, damit die Details auch dann bleiben, wenn am Abend niemand
//     das Spiel geöffnet hat. Welche Spiele das sind, sagt OpenLigaDB — an
//     Tagen ohne Länderspiel kostet der Lauf keinen einzigen Abruf.
//
// Aufruf:
//   POST /functions/v1/laenderspiel  { "anstoss": "2026-11-13T19:45:00Z" }
//   POST /functions/v1/laenderspiel  { "sammeln": true }  + x-sync-secret
//
// Antwort: { "detail": {...} | null }. `detail` hat die Feldnamen, die die App
// auch von der `sportmonks`-Function kennt (lineups, events, stats, …).

import { createClient } from "npm:@supabase/supabase-js@2";

const BASE = "https://v3.football.api-sports.io";
const KEY = Deno.env.get("API_FOOTBALL_KEY");
const DEUTSCHLAND = 25;

/// Unter so vielen Rest-Abrufen des Tages fragt die Function nicht mehr nach
/// und liefert, was sie hat. Der Rest bleibt für den nächtlichen Lauf.
const RESERVE = 8;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sync-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
type Any = any;

let restHeute: number | null = null;

async function afGet(pfad: string): Promise<Any[]> {
  const res = await fetch(`${BASE}${pfad}`, {
    headers: { "x-apisports-key": KEY! },
  });
  const rest = res.headers.get("x-ratelimit-requests-remaining");
  if (rest != null && !Number.isNaN(Number(rest))) restHeute = Number(rest);
  if (!res.ok) throw new Error(`API-Football ${res.status} (${pfad})`);
  const body = await res.json();
  // API-Football meldet Fehler im Body, nicht im Status.
  const fehler = body?.errors;
  if (fehler && !Array.isArray(fehler) && Object.keys(fehler).length > 0) {
    throw new Error(`API-Football: ${JSON.stringify(fehler)}`);
  }
  return body?.response ?? [];
}

const tag = (d: Date) => d.toISOString().slice(0, 10);

/// Liegt das Datum im Fenster des Gratis-Tarifs (gestern bis morgen, UTC)?
function imFenster(datum: string, jetzt: Date): boolean {
  const t = 86400000;
  return [-t, 0, t].some((d) => tag(new Date(jetzt.getTime() + d)) === datum);
}

const LIVE = new Set(["1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT"]);
const AUS = new Set(["FT", "AET", "PEN"]);

// --- Umformen in die Feldnamen der App -----------------------------------

const STATS: [string, string][] = [
  ["Ball Possession", "Ballbesitz %"],
  ["Total Shots", "Torschüsse"],
  ["Shots on Goal", "Schüsse aufs Tor"],
  ["Corner Kicks", "Ecken"],
  ["Offsides", "Abseits"],
  ["Fouls", "Fouls"],
  ["Yellow Cards", "Gelbe Karten"],
  ["Red Cards", "Rote Karten"],
  ["Goalkeeper Saves", "Paraden"],
  ["Total passes", "Pässe"],
  ["Passes accurate", "Genaue Pässe"],
];

function zahl(v: Any): number {
  if (v == null) return 0;
  const n = Number(String(v).replace("%", ""));
  return Number.isFinite(n) ? n : 0;
}

/// Ereignistyp in der Schreibweise, die der Spielverlauf der App kennt
/// (Sportmonks-Klartext). `null` = nicht anzeigen (verschossener Elfmeter).
function typ(e: Any): string | null {
  const t = String(e.type ?? "").toLowerCase();
  const d = String(e.detail ?? "").toLowerCase();
  if (t === "goal") {
    if (d.includes("missed")) return null;
    if (d.includes("own")) return "Own Goal";
    if (d.includes("penalty")) return "Penalty";
    return "Goal";
  }
  if (t === "card") {
    if (d.includes("second")) return "Yellowred card";
    if (d.includes("red")) return "Redcard";
    return "Yellowcard";
  }
  if (t === "subst") return "Substitution";
  if (t === "var") return "VAR";
  return null;
}

export function umformen(f: Any) {
  const heimId = f.teams?.home?.id;
  const lineups: Any[] = [];
  const formation: Record<string, string | null> = {};
  for (const l of f.lineups ?? []) {
    const heim = l.team?.id === heimId;
    formation[heim ? "home" : "away"] = l.formation ?? null;
    (l.startXI ?? []).forEach((s: Any, i: number) => {
      const p = s.player ?? {};
      lineups.push({
        name: p.name ?? "?",
        for_home: heim,
        starting: true,
        player_id: p.id ?? null,
        number: p.number ?? null,
        // Reihenfolge der Quelle: Torwart zuerst, dann Reihe für Reihe.
        position: i + 1,
        field: p.grid ?? null,
      });
    });
    for (const s of l.substitutes ?? []) {
      const p = s.player ?? {};
      lineups.push({
        name: p.name ?? "?",
        for_home: heim,
        starting: false,
        player_id: p.id ?? null,
        number: p.number ?? null,
        position: null,
        field: null,
      });
    }
  }

  const events: Any[] = [];
  let h = 0, a = 0;
  for (const e of f.events ?? []) {
    const t = typ(e);
    if (t == null) continue;
    const heim = e.team?.id === heimId;
    const istTor = t === "Goal" || t === "Penalty" || t === "Own Goal";
    if (istTor) heim ? h++ : a++;
    const wechsel = t === "Substitution";
    events.push({
      minute: e.time?.elapsed ?? 0,
      extra: e.time?.extra ?? null,
      type: t,
      for_home: heim,
      // Beim Wechsel steht bei API-Football der **Ausgewechselte** unter
      // `player` und der Eingewechselte unter `assist` (nachgesehen an Köln–
      // Leverkusen, 08.11.2026: Krauß stand in der Startelf und ging in der
      // 74.). Die App erwartet es wie bei Sportmonks andersherum.
      player: wechsel ? e.assist?.name ?? null : e.player?.name ?? null,
      player_id: wechsel ? e.assist?.id ?? null : e.player?.id ?? null,
      related: wechsel
        ? e.player?.name ?? null
        : t === "VAR"
        ? e.detail ?? null
        : istTor
        ? e.assist?.name ?? null
        : null,
      related_player_id: wechsel ? e.player?.id ?? null : null,
      result: istTor ? `${h}-${a}` : null,
    });
  }

  const statsHeim = (f.statistics ?? []).find((s: Any) =>
    s.team?.id === heimId
  )?.statistics ?? [];
  const statsGast = (f.statistics ?? []).find((s: Any) =>
    s.team?.id !== heimId
  )?.statistics ?? [];
  const wert = (liste: Any[], name: string) =>
    liste.find((s: Any) => s.type === name)?.value;
  const stats = STATS
    .filter(([q]) => wert(statsHeim, q) != null || wert(statsGast, q) != null)
    .map(([q, label]) => ({
      label,
      home: zahl(wert(statsHeim, q)),
      away: zahl(wert(statsGast, q)),
    }));

  return {
    af_id: f.fixture?.id ?? null,
    status: f.fixture?.status?.short ?? null,
    minute: f.fixture?.status?.elapsed ?? null,
    extra: f.fixture?.status?.extra ?? null,
    home_score: f.goals?.home ?? null,
    away_score: f.goals?.away ?? null,
    referee: f.fixture?.referee ?? null,
    home_formation: formation.home ?? null,
    away_formation: formation.away ?? null,
    lineups,
    events,
    stats,
  };
}

// --- Holen mit Cache ------------------------------------------------------

/// Wie lange ein gemerkter Stand gilt, gemessen am Anstoß. Mit 120 s im Spiel
/// kostet eine Partie samt Vorlauf rund 70 Abrufe — innerhalb der 100.
function ttlSekunden(anstoss: Date, jetzt: Date, status: string | null) {
  const bis = (anstoss.getTime() - jetzt.getTime()) / 60000;
  if (status && LIVE.has(status)) return 120;
  if (bis > 90) return 3600; // vor dem Fenster der Aufstellung
  if (bis > 0) return 600; // Aufstellung kommt rund eine Stunde vorher
  if (bis > -150) return 120; // läuft, auch wenn die Quelle es noch nicht weiß
  return 600; // vorbei, Endstand noch nicht sicher
}

async function holeSpiel(
  supabase: Any,
  anstoss: Date,
  erzwingen = false,
): Promise<Any | null> {
  const jetzt = new Date();
  const datum = tag(anstoss);
  const key = `af:de:${datum}`;
  const { data: zeile } = await supabase
    .from("sportmonks_cache")
    .select("fetched_at, payload")
    .eq("cache_key", key)
    .maybeSingle();
  const gemerkt = zeile?.payload ?? null;
  if (gemerkt?.final) return gemerkt.detail ?? null;

  const alter = zeile
    ? (jetzt.getTime() - new Date(zeile.fetched_at).getTime()) / 1000
    : Infinity;
  const frisch = alter <
    ttlSekunden(anstoss, jetzt, gemerkt?.detail?.status ?? null);
  if (!erzwingen && frisch) return gemerkt?.detail ?? null;
  if (!imFenster(datum, jetzt)) return gemerkt?.detail ?? null;
  if (gemerkt?.rest != null && gemerkt.rest < RESERVE && !erzwingen) {
    return gemerkt?.detail ?? null;
  }

  let afId: number | null = gemerkt?.af_id ?? null;
  if (afId == null) {
    // **Nur nach Datum, ohne Team.** `team` verlangt zusätzlich `season`,
    // und die sperrt der Gratis-Tarif für die laufende Saison (gemessen
    // 09.11.2026: „The Season field is required"). Ein Abruf liefert alle
    // Spiele des Tages (rund 1.200); Deutschland wird hier herausgesucht.
    const liste = (await afGet(`/fixtures?date=${datum}`)).filter((x: Any) =>
      x.teams?.home?.id === DEUTSCHLAND || x.teams?.away?.id === DEUTSCHLAND
    );
    // Das Spiel, dessen Anstoß am nächsten liegt (es gibt praktisch nur eins).
    liste.sort((x: Any, y: Any) =>
      Math.abs(x.fixture.timestamp * 1000 - anstoss.getTime()) -
      Math.abs(y.fixture.timestamp * 1000 - anstoss.getTime())
    );
    afId = liste[0]?.fixture?.id ?? null;
  }

  let detail: Any = gemerkt?.detail ?? null;
  if (afId != null) {
    const [f] = await afGet(`/fixtures?id=${afId}`);
    if (f) detail = umformen(f);
  }
  // **Endgültig erst mit Abstand zum Abpfiff:** Die Quelle trägt Karten und
  // Wechsel teils nach. Danach wird nie wieder gefragt.
  const final = detail != null && AUS.has(detail.status) &&
    jetzt.getTime() - anstoss.getTime() > 150 * 60000;

  await supabase.from("sportmonks_cache").upsert({
    cache_key: key,
    fetched_at: jetzt.toISOString(),
    payload: { af_id: afId, final, rest: restHeute, detail },
  });
  return detail;
}

/// Nächtlicher Lauf: Länderspiele der letzten 30 Stunden laut OpenLigaDB.
async function sammeln(supabase: Any) {
  const jetzt = new Date();
  const jahr = jetzt.getUTCFullYear();
  const ergebnis: Any[] = [];
  for (const j of [jahr, jahr - 1]) {
    const res = await fetch(`https://api.openligadb.de/getmatchdata/DFBN/${j}`);
    if (!res.ok) continue;
    const spiele = await res.json();
    for (const m of spiele ?? []) {
      const anstoss = new Date(m.matchDateTimeUTC);
      const vor = jetzt.getTime() - anstoss.getTime();
      if (vor < 2 * 3600000 || vor > 30 * 3600000) continue;
      const d = await holeSpiel(supabase, anstoss, true);
      ergebnis.push({ anstoss: m.matchDateTimeUTC, status: d?.status ?? null });
    }
  }
  return ergebnis;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (!KEY) return json({ error: "API_FOOTBALL_KEY nicht gesetzt." }, 500);

  let body: { anstoss?: string; sammeln?: boolean } = {};
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Ungültiger Body." }, 400);
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    if (body.sammeln) {
      const secret = Deno.env.get("SYNC_SECRET");
      if (!secret || req.headers.get("x-sync-secret") !== secret) {
        return json({ error: "forbidden" }, 403);
      }
      return json({ gesammelt: await sammeln(supabase), rest: restHeute });
    }
    const anstoss = new Date(body.anstoss ?? "");
    if (Number.isNaN(anstoss.getTime())) {
      return json({ error: "anstoss fehlt." }, 400);
    }
    return json({ detail: await holeSpiel(supabase, anstoss) });
  } catch (e) {
    return json({ error: String(e) }, 502);
  }
});
