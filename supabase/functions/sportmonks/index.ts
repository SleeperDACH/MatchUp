// Sportmonks-Proxy: hält den geheimen SPORTMONKS_API_KEY serverseitig und
// liefert dem Client normalisierte Fixtures/Tabellen/Spieldetails. Eine Abfrage
// versorgt alle Nutzer und wird in public.sportmonks_cache mit TTL gecacht.
//
// Aufruf (Client, via supabase.functions.invoke mit Anon/User-JWT):
//   POST /functions/v1/sportmonks
//   Body: { "kind": "seasonFixtures", "leagueKey": "82" }
//         { "kind": "standings",      "leagueKey": "82" }
//         { "kind": "fixture",        "fixtureId": "19734892" }
//
// leagueKey = Sportmonks-League-ID (LeagueInfo.providerLeagueKey der App).

import { createClient } from "npm:@supabase/supabase-js@2";

const BASE = "https://api.sportmonks.com/v3/football";
// Sportmonks-WAF blockt ohne Browser-User-Agent mit 403.
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120 Safari/537.36";

// Nur diese Ligen sind erlaubt (die 5 im Sportmonks-Plan).
const ALLOWED_LEAGUES = new Set(["82", "85", "88", "109", "1740"]);

// TTL je Ressource (Sekunden): Fixtures kurz (Live), Tabelle länger.
const TTL = {
  seasonFixtures: 60,
  standings: 300,
  fixture: 45,
  season: 21600,
  topscorers: 3600,
  teamFixtures: 120,
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const KEY = Deno.env.get("SPORTMONKS_API_KEY");

// deno-lint-ignore no-explicit-any
async function smGet(path: string): Promise<any> {
  const sep = path.includes("?") ? "&" : "?";
  const res = await fetch(`${BASE}${path}${sep}api_token=${KEY}`, {
    headers: { "User-Agent": UA, Accept: "application/json" },
  });
  if (!res.ok) {
    throw new Error(`Sportmonks HTTP ${res.status} für ${path}`);
  }
  return await res.json();
}

// Auflösen der aktuellen Saison-ID einer Liga (gecacht, langlebig).
// deno-lint-ignore no-explicit-any
async function currentSeasonId(supabase: any, leagueKey: string): Promise<number> {
  const ck = `season:${leagueKey}`;
  const cached = await readCache(supabase, ck, TTL.season);
  if (cached) return cached as number;
  const r = await smGet(`/leagues/${leagueKey}?include=currentSeason`);
  const cs = r?.data?.currentseason ?? r?.data?.current_season;
  const id = cs?.id;
  if (!id) throw new Error(`Keine aktuelle Saison für Liga ${leagueKey}`);
  await writeCache(supabase, ck, id);
  return id;
}

function isoUtc(s: string | null | undefined): string | null {
  if (!s) return null;
  // Sportmonks liefert UTC als "YYYY-MM-DD HH:MM:SS".
  return s.replace(" ", "T") + "Z";
}

// deno-lint-ignore no-explicit-any
function normParticipant(p: any) {
  return {
    id: p.id,
    name: p.name,
    short: p.short_code ?? p.name,
    img: teamImg(p.image_path),
    location: p?.meta?.location ?? null, // "home" | "away"
  };
}

// Sportmonks liefert für Teams ohne Logo ein generisches „team_placeholder.png".
// Das ist kein echtes Wappen → als „kein Logo" behandeln (Client zeigt dann die
// Initialen).
function teamImg(path: string | null | undefined): string | null {
  if (!path) return null;
  return path.includes("placeholder") ? null : path;
}

// deno-lint-ignore no-explicit-any
function currentScore(scores: any[], location: string): number | null {
  const e = (scores ?? []).find(
    (s) => s.description === "CURRENT" && s?.score?.participant === location,
  );
  return e ? (e.score?.goals ?? null) : null;
}

// Pokal-Runde aus dem Sportmonks-Stage-Namen (englisch) → Ordinalzahl 1–6
// (DFB-Pokal: 1. Runde … Finale). Der deutsche Anzeigename wird im Client
// aus der Ordinalzahl gebildet.
function cupStageOrder(stageName: string | undefined): number {
  const s = (stageName ?? "").toLowerCase();
  if (!s) return 0;
  if (s.includes("final") && !s.includes("semi") && !s.includes("quarter")) {
    return 6;
  }
  if (s.includes("semi")) return 5;
  if (s.includes("quarter")) return 4;
  if (s.includes("16")) return 3;
  if (s.includes("2nd") || s.includes("second")) return 2;
  if (s.includes("1st") || s.includes("first")) return 1;
  return 0;
}

// deno-lint-ignore no-explicit-any
function normFixture(f: any) {
  const parts = (f.participants ?? []).map(normParticipant);
  const home = parts.find((p: { location: string }) => p.location === "home") ??
    parts[0] ?? null;
  const away = parts.find((p: { location: string }) => p.location === "away") ??
    parts[1] ?? null;
  const roundName = f.round?.name ?? "";
  // Liga: Spieltagnummer aus round.name. Pokal (kein round) → Stage-Ordinalzahl.
  const round = Number(roundName) || cupStageOrder(f.stage?.name);
  return {
    id: f.id,
    starting_at: isoUtc(f.starting_at ?? f.starting_at_timestamp_str),
    state: f.state?.state ?? f.state?.developer_name ?? "NS",
    round,
    round_name: roundName || (f.stage?.name ?? ""),
    league_name: f.league?.name ?? null,
    league_image: f.league?.image_path ?? null,
    home,
    away,
    home_score: home ? currentScore(f.scores, "home") : null,
    away_score: away ? currentScore(f.scores, "away") : null,
  };
}

// Spielplan eines Teams über alle (im Plan verfügbaren) Wettbewerbe: die
// letzten ~6 Wochen und die nächsten ~5 Monate. Europäische Wettbewerbe sind
// im Trial-Plan nicht enthalten.
async function teamFixtures(teamId: string) {
  const now = Date.now();
  const d = (offsetDays: number) =>
    new Date(now + offsetDays * 86400000).toISOString().slice(0, 10);
  const r = await smGet(
    `/fixtures/between/${d(-45)}/${d(150)}/${teamId}` +
      `?include=participants;scores;state;round;stage;league&per_page=50`,
  );
  // deno-lint-ignore no-explicit-any
  const fixtures = ((r?.data ?? []) as any[])
    .map(normFixture)
    .sort((a, b) => (a.starting_at ?? "").localeCompare(b.starting_at ?? ""));
  return { fixtures };
}

async function seasonFixtures(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  leagueKey: string,
) {
  const season = await currentSeasonId(supabase, leagueKey);
  // deno-lint-ignore no-explicit-any
  const all: any[] = [];
  let page = 1;
  // Bis zu ~10 Seiten à 50 = 500 Spiele (reicht für eine Ligasaison).
  for (; page <= 12; page++) {
    const r = await smGet(
      `/fixtures?filters=fixtureSeasons:${season}` +
        `&include=participants;scores;state;round;stage&per_page=50&page=${page}`,
    );
    const data = r?.data ?? [];
    for (const f of data) all.push(normFixture(f));
    const pg = r?.pagination ?? r?.meta?.pagination;
    if (!pg?.has_more) break;
  }
  return { season, fixtures: all };
}

async function standings(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  leagueKey: string,
) {
  const season = await currentSeasonId(supabase, leagueKey);
  const r = await smGet(
    `/standings/seasons/${season}?include=participant;details.type`,
  );
  const detail = (
    // deno-lint-ignore no-explicit-any
    row: any,
    code: string,
  ): number => {
    const d = (row.details ?? []).find(
      // deno-lint-ignore no-explicit-any
      (x: any) => (x.type?.code ?? x.type?.developer_name) === code,
    );
    return d?.value ?? 0;
  };
  // deno-lint-ignore no-explicit-any
  const rows = (r?.data ?? []).map((row: any) => ({
    position: row.position,
    points: row.points ?? 0,
    team: row.participant ? normParticipant(row.participant) : null,
    played: detail(row, "overall-matches-played"),
    won: detail(row, "overall-won"),
    draw: detail(row, "overall-draw"),
    lost: detail(row, "overall-lost"),
    goals_for: detail(row, "overall-goals-for"),
    goals_against: detail(row, "overall-goals-against"),
  }));
  // Manche Ligen (z. B. Frauen-Bundesliga) liefern vor Saisonstart keine
  // Standings. Dann eine Null-Tabelle aus den teilnehmenden Teams bauen, damit
  // wenigstens alle Mannschaften erscheinen (alphabetisch, 0 Punkte).
  if (rows.length === 0) {
    const t = await smGet(`/seasons/${season}?include=teams`);
    // deno-lint-ignore no-explicit-any
    const teams = ((t?.data?.teams ?? []) as any[])
      .map(normParticipant)
      .sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));
    const zeroRows = teams.map((team, i) => ({
      position: i + 1,
      points: 0,
      team,
      played: 0,
      won: 0,
      draw: 0,
      lost: 0,
      goals_for: 0,
      goals_against: 0,
    }));
    return { season, standings: zeroRows, provisional: true };
  }
  return { season, standings: rows };
}

// deno-lint-ignore no-explicit-any
// Kuratierte Auswahl an Statistiken (Sportmonks-Typname) in Anzeigereihenfolge.
const STAT_ORDER: [string, string][] = [
  ["Ball Possession %", "Ballbesitz %"],
  ["Shots Total", "Torschüsse"],
  ["Shots On Target", "Schüsse aufs Tor"],
  ["Corners", "Ecken"],
  ["Offsides", "Abseits"],
  ["Fouls", "Fouls"],
  ["Yellowcards", "Gelbe Karten"],
  ["Redcards", "Rote Karten"],
  ["Saves", "Paraden"],
  ["Passes", "Pässe"],
  ["Successful Passes Percentage", "Passquote %"],
];

// deno-lint-ignore no-explicit-any
async function fixtureDetail(fixtureId: string) {
  const r = await smGet(
    `/fixtures/${fixtureId}` +
      `?include=participants;scores;state;round;events.type;venue;` +
      `lineups.player;statistics.type;league;formations`,
  );
  const f = r?.data;
  if (!f) throw new Error(`Fixture ${fixtureId} nicht gefunden`);
  const base = normFixture(f);
  const parts = (f.participants ?? []).map(normParticipant);
  const homeId = parts.find((p: { location: string }) => p.location === "home")?.id;
  const awayId = parts.find((p: { location: string }) => p.location === "away")?.id;
  // Tore aus den Events (best effort): Typen mit "goal" im Namen.
  // deno-lint-ignore no-explicit-any
  const goals = (f.events ?? [])
    // deno-lint-ignore no-explicit-any
    .filter((e: any) => {
      const n = (e.type?.developer_name ?? e.type?.code ?? "").toUpperCase();
      return n.includes("GOAL");
    })
    // deno-lint-ignore no-explicit-any
    .map((e: any) => {
      const dev = (e.type?.developer_name ?? "").toUpperCase();
      const [h, a] = String(e.result ?? "").split("-").map((x) => Number(x));
      return {
        minute: e.minute ?? null,
        scorer: e.player_name ?? "Tor",
        score_home: Number.isFinite(h) ? h : null,
        score_away: Number.isFinite(a) ? a : null,
        for_home: e.participant_id === homeId,
        penalty: dev.includes("PENALTY"),
        own_goal: dev.includes("OWNGOAL") || dev.includes("OWN_GOAL"),
      };
    });
  // Aufstellungen: Startelf (type "Lineup") und Bank (type "Bench") je Team.
  // deno-lint-ignore no-explicit-any
  const lineups = (f.lineups ?? []).map((l: any) => ({
    for_home: l.team_id === homeId,
    player_id: l.player_id ?? null,
    name: l.player?.name ?? l.player_name ?? "?",
    number: l.jersey_number ?? null,
    position: l.formation_position ?? null,
    field: l.formation_field ?? null, // "row:col" für die Feldaufstellung
    starting: l.type_id === 11, // 11 = Startelf, 12 = Bank
  }));

  // Formationen (z. B. „4-2-3-1") je Team.
  // deno-lint-ignore no-explicit-any
  let homeFormation: string | null = null;
  // deno-lint-ignore no-explicit-any
  let awayFormation: string | null = null;
  for (const fm of (f.formations ?? [])) {
    if (fm.participant_id === homeId) homeFormation = fm.formation ?? null;
    else if (fm.participant_id === awayId) awayFormation = fm.formation ?? null;
  }

  // Statistiken: je Typ Heim-/Auswärtswert; nur die kuratierte Auswahl.
  // deno-lint-ignore no-explicit-any
  const statMap: Record<string, { home: number | null; away: number | null }> = {};
  for (const s of (f.statistics ?? [])) {
    const name = s.type?.name;
    if (!name) continue;
    const val = s.data?.value ?? null;
    statMap[name] = statMap[name] ?? { home: null, away: null };
    if (s.participant_id === homeId || s.location === "home") {
      statMap[name].home = val;
    } else if (s.participant_id === awayId || s.location === "away") {
      statMap[name].away = val;
    }
  }
  const stats = STAT_ORDER
    .filter(([key]) => statMap[key] &&
      (statMap[key].home != null || statMap[key].away != null))
    .map(([key, label]) => ({
      label,
      home: statMap[key].home ?? 0,
      away: statMap[key].away ?? 0,
    }));

  // Spielverlauf: Tore, Karten, Wechsel, VAR nach Minute sortiert.
  // deno-lint-ignore no-explicit-any
  const events = (f.events ?? [])
    // deno-lint-ignore no-explicit-any
    .map((e: any) => ({
      minute: e.minute ?? null,
      extra: e.extra_minute ?? null,
      type: e.type?.name ?? "",
      player: e.player_name ?? null,
      player_id: e.player_id ?? null,
      related: e.related_player_name ?? null,
      for_home: e.participant_id === homeId,
      result: e.result ?? null,
    }))
    // deno-lint-ignore no-explicit-any
    .filter((e: any) => e.minute != null)
    // deno-lint-ignore no-explicit-any
    .sort((a: any, b: any) =>
      (a.minute - b.minute) || ((a.extra ?? 0) - (b.extra ?? 0)));

  return {
    ...base,
    venue: f.venue ? { name: f.venue.name, city: f.venue.city_name } : null,
    league_key: f.league?.id != null ? String(f.league.id) : null,
    league_name: f.league?.name ?? null,
    home_formation: homeFormation,
    away_formation: awayFormation,
    goals,
    lineups,
    stats,
    events,
  };
}

// Torschützenliste (type_id 83 = Tore) — ausschließlich die AKTUELLE Saison.
// Vor Saisonstart ist die Liste leer (kein Rückgriff auf die letzte Saison,
// damit keine „alten" Tore angezeigt werden).
async function topScorers(leagueKey: string) {
  const r = await smGet(`/leagues/${leagueKey}?include=currentSeason`);
  const cs = r?.data?.currentseason ?? r?.data?.current_season;
  const empty = {
    season: cs?.id ?? null,
    season_name: cs?.name ?? null,
    current: true,
    scorers: [],
  };
  if (!cs?.id) return empty;

  const ts = await smGet(
    `/topscorers/seasons/${cs.id}?include=player;participant&per_page=25`,
  );
  // deno-lint-ignore no-explicit-any
  const goals = ((ts?.data ?? []) as any[]).filter((t) => t.type_id === 83);
  if (goals.length === 0) return empty;

  goals.sort((a, b) => (a.position ?? 999) - (b.position ?? 999));
  return {
    season: cs.id,
    season_name: cs.name ?? null,
    current: true,
    scorers: goals.map((t) => ({
      position: t.position,
      goals: t.total,
      player_name: t.player?.name ?? "?",
      player_img: t.player?.image_path ?? null,
      team_name: t.participant?.name ?? null,
      team_img: teamImg(t.participant?.image_path),
    })),
  };
}

// --- Cache ---------------------------------------------------------------
// deno-lint-ignore no-explicit-any
async function readCache(supabase: any, key: string, ttlSec: number) {
  const { data } = await supabase
    .from("sportmonks_cache")
    .select("fetched_at, payload")
    .eq("cache_key", key)
    .maybeSingle();
  if (!data) return null;
  const ageSec = (Date.now() - new Date(data.fetched_at).getTime()) / 1000;
  return ageSec < ttlSec ? data.payload : null;
}
// deno-lint-ignore no-explicit-any
async function writeCache(supabase: any, key: string, payload: unknown) {
  await supabase.from("sportmonks_cache").upsert({
    cache_key: key,
    fetched_at: new Date().toISOString(),
    payload,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (!KEY) return json({ error: "SPORTMONKS_API_KEY nicht gesetzt." }, 500);

  let body: {
    kind?: string;
    leagueKey?: string;
    fixtureId?: string;
    teamId?: string;
    nocache?: boolean;
  } = {};
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Ungültiger Body." }, 400);
  }
  const { kind, leagueKey, fixtureId, teamId } = body;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  // Cache umgehen (Force-Refresh) — liest frisch, schreibt aber weiter.
  const rc = (ck: string, ttl: number) =>
    body.nocache === true
      ? Promise.resolve(null)
      : readCache(supabase, ck, ttl);

  try {
    if (kind === "seasonFixtures" || kind === "standings") {
      if (!leagueKey || !ALLOWED_LEAGUES.has(leagueKey)) {
        return json({ error: "Unbekannte Liga." }, 400);
      }
      const ck = `${kind}:${leagueKey}`;
      const cached = await rc(ck, TTL[kind]);
      if (cached) return json(cached);
      const payload = kind === "seasonFixtures"
        ? await seasonFixtures(supabase, leagueKey)
        : await standings(supabase, leagueKey);
      await writeCache(supabase, ck, payload);
      return json(payload);
    }
    if (kind === "fixture") {
      if (!fixtureId) return json({ error: "fixtureId fehlt." }, 400);
      const ck = `fixture:${fixtureId}`;
      const cached = await rc(ck, TTL.fixture);
      if (cached) return json(cached);
      const payload = await fixtureDetail(fixtureId);
      await writeCache(supabase, ck, payload);
      return json(payload);
    }
    if (kind === "topscorers") {
      if (!leagueKey || !ALLOWED_LEAGUES.has(leagueKey)) {
        return json({ error: "Unbekannte Liga." }, 400);
      }
      const ck = `topscorers:${leagueKey}`;
      const cached = await rc(ck, TTL.topscorers);
      if (cached) return json(cached);
      const payload = await topScorers(leagueKey);
      await writeCache(supabase, ck, payload);
      return json(payload);
    }
    if (kind === "teamFixtures") {
      if (!teamId || !/^\d+$/.test(teamId)) {
        return json({ error: "Ungültige teamId." }, 400);
      }
      const ck = `teamFixtures:${teamId}`;
      const cached = await rc(ck, TTL.teamFixtures);
      if (cached) return json(cached);
      const payload = await teamFixtures(teamId);
      await writeCache(supabase, ck, payload);
      return json(payload);
    }
    return json({ error: "Unbekannter kind." }, 400);
  } catch (e) {
    return json({ error: String(e) }, 502);
  }
});
