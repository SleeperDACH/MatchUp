// Fixture-Sync: spiegelt Spielplan + Ergebnisse aus OpenLigaDB in die
// Tabelle public.fixtures, damit die Tipp-Deadlines (RLS: Tippen nur vor
// Anstoß) serverseitig gegen echte Anstoßzeiten geprüft werden können.
//
// Aufruf (Cron oder manuell):
//   POST /functions/v1/sync-fixtures            → aktuelle Saison
//   POST /functions/v1/sync-fixtures?season=2025 → bestimmte Saison
//
// Die Function ist ohne JWT erreichbar (--no-verify-jwt), verlangt aber
// den Header `x-sync-secret` (Secret SYNC_SECRET in den Function-Secrets).
//
// Mapping identisch zu lib/core/data/openligadb/openligadb_provider.dart.

import { createClient } from "npm:@supabase/supabase-js@2";

// Die fünf deutschen Ligen werden aus **Sportmonks** gespiegelt (Fixture-IDs
// `sportmonks:<id>`, konsistent zum Client SupabaseSportmonksProvider).
// Turniere/WM bleiben auf OpenLigaDB (World Cup nicht im Sportmonks-Plan).
const SM_LEAGUES: { leagueId: string; key: string }[] = [
  { leagueId: "bundesliga", key: "82" },
  { leagueId: "bundesliga2", key: "85" },
  { leagueId: "liga3", key: "88" },
  { leagueId: "dfb_pokal", key: "109" },
  { leagueId: "frauen_bundesliga", key: "1740" },
];

const OL_LEAGUES: { leagueId: string; providerKey: string; fixedSeason?: number }[] = [
  { leagueId: "wm2026", providerKey: "wm26", fixedSeason: 2026 },
];

function currentSeason(now: Date): number {
  // Saison = Startjahr: ab Juli zählt das laufende Jahr (2025/26 → 2025).
  return now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1;
}

// ---------------------------------------------------------------------
// Sportmonks-Spiegelung (Key serverseitig; WAF braucht Browser-User-Agent).
// Mapping (Status/Score/ID) identisch zum Client SupabaseSportmonksProvider.
// ---------------------------------------------------------------------
const SM_BASE = "https://api.sportmonks.com/v3/football";
const SM_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120 Safari/537.36";
const SM_KEY = Deno.env.get("SPORTMONKS_API_KEY");

// deno-lint-ignore no-explicit-any
async function smGet(path: string): Promise<any> {
  const sep = path.includes("?") ? "&" : "?";
  const res = await fetch(`${SM_BASE}${path}${sep}api_token=${SM_KEY}`, {
    headers: { "User-Agent": SM_UA, Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`Sportmonks HTTP ${res.status} für ${path}`);
  return await res.json();
}

async function smSeasonId(leagueKey: string): Promise<number> {
  const r = await smGet(`/leagues/${leagueKey}?include=currentSeason`);
  const cs = r?.data?.currentseason ?? r?.data?.current_season;
  if (!cs?.id) throw new Error(`Keine aktuelle Saison für Liga ${leagueKey}`);
  return cs.id;
}

function smStatus(state: string): string {
  const s = (state || "NS").toUpperCase();
  if (["FT", "AET", "FT_PEN", "AWARDED", "WALKOVER"].includes(s)) {
    return "finished";
  }
  if (
    s.startsWith("INPLAY") ||
    ["HT", "BREAK", "ET", "EXTRA_TIME", "PENALTIES"].includes(s) ||
    (s.includes("PEN") && s !== "FT_PEN")
  ) return "live";
  return "scheduled";
}

// deno-lint-ignore no-explicit-any
function smScore(scores: any[], loc: string): number | null {
  const e = (scores ?? []).find(
    (x) => x.description === "CURRENT" && x?.score?.participant === loc,
  );
  return e ? (e.score?.goals ?? null) : null;
}

// deno-lint-ignore no-explicit-any
function smFixtureRow(f: any, leagueId: string, season: number) {
  const parts = f.participants ?? [];
  // deno-lint-ignore no-explicit-any
  const home = parts.find((p: any) => p?.meta?.location === "home") ?? parts[0];
  // deno-lint-ignore no-explicit-any
  const away = parts.find((p: any) => p?.meta?.location === "away") ?? parts[1];
  return {
    id: `sportmonks:${f.id}`,
    league_id: leagueId,
    season,
    round: Number(f.round?.name) || 0,
    kickoff: String(f.starting_at ?? "").replace(" ", "T") + "Z",
    home_name: home?.name ?? "?",
    away_name: away?.name ?? "?",
    home_score: home ? smScore(f.scores, "home") : null,
    away_score: away ? smScore(f.scores, "away") : null,
    status: smStatus(f.state?.state),
  };
}

// deno-lint-ignore no-explicit-any
async function smSeasonFixtures(leagueKey: string): Promise<any[]> {
  const season = await smSeasonId(leagueKey);
  // deno-lint-ignore no-explicit-any
  const all: any[] = [];
  for (let page = 1; page <= 12; page++) {
    const r = await smGet(
      `/fixtures?filters=fixtureSeasons:${season}` +
        `&include=participants;scores;state;round&per_page=50&page=${page}`,
    );
    for (const f of (r?.data ?? [])) all.push(f);
    const pg = r?.pagination ?? r?.meta?.pagination;
    if (!pg?.has_more) break;
  }
  return all;
}

// deno-lint-ignore no-explicit-any
function toFixtureRow(m: any, leagueId: string, season: number, now: Date) {
  // deno-lint-ignore no-explicit-any
  const results = (m.matchResults ?? []) as any[];
  const endResult = results.find((r) => r.resultTypeID === 2);
  // Maßgebliches Ergebnis für die Wertung: K.-o.-Spiele zählen nach
  // Verlängerung (120 Min), Elfmeterschießen (Typ 5) nicht. Daher hat
  // „nach Verlängerung" (Typ 4) Vorrang vor dem „Endergebnis" (Typ 2);
  // Typ 5 wird nie genommen. Muss zu OpenLigaDbProvider._finalScore passen.
  const finalResult = results.find((r) => r.resultTypeID === 4) ?? endResult;
  const lastGoal = (m.goals ?? []).at(-1);
  const kickoff = new Date(m.matchDateTimeUTC);
  const started = kickoff <= now;

  // OpenLigaDB pflegt das „Endergebnis" (resultTypeID 2) teils schon während
  // des Spiels (WM-Feed). Beendet nur: expliziter Haken ODER Endergebnis liegt
  // vor UND Anstoß ist >3 h her. Sonst ist ein angepfiffenes Spiel LIVE.
  // Muss zu OpenLigaDbProvider.parseMatch in der App passen.
  const longOver = now.getTime() > kickoff.getTime() + 3 * 60 * 60 * 1000;
  const finished = m.matchIsFinished === true || (!!endResult && longOver);

  let homeScore: number | null = null;
  let awayScore: number | null = null;
  if (finished && finalResult) {
    homeScore = finalResult.pointsTeam1;
    awayScore = finalResult.pointsTeam2;
  } else if (started) {
    // Live-Stand: Torliste, sonst Endergebnis, sonst 0:0.
    if (lastGoal) {
      homeScore = lastGoal.scoreTeam1 ?? 0;
      awayScore = lastGoal.scoreTeam2 ?? 0;
    } else if (endResult) {
      homeScore = endResult.pointsTeam1;
      awayScore = endResult.pointsTeam2;
    } else {
      homeScore = 0;
      awayScore = 0;
    }
  }

  return {
    id: `openligadb:${m.matchID}`,
    league_id: leagueId,
    season,
    round: m.group?.groupOrderID ?? 0,
    kickoff: m.matchDateTimeUTC,
    home_name: m.team1?.teamName ?? "?",
    away_name: m.team2?.teamName ?? "?",
    home_score: homeScore,
    away_score: awayScore,
    status: finished ? "finished" : started ? "live" : "scheduled",
  };
}

// ---------------------------------------------------------------------
// Quoten-Freeze: friert zum Anstoß die 1X2-Quote je Spiel ein (Tabelle
// fixture_odds) als Grundlage für den Quoten-Bonus in der Wertung. Quelle
// und Matching identisch zum Client (lib/core/data/odds/*) — der Resolver
// übersetzt die englischen Quoten-Teamnamen auf die OpenLigaDB-shortNames
// (für die WM die FIFA-Codes). Bei Änderungen Client mit anpassen.
// ---------------------------------------------------------------------

const ODDS_SPORT: Record<string, string> = {
  wm2026: "soccer_fifa_world_cup",
  bundesliga: "soccer_germany_bundesliga",
  bundesliga2: "soccer_germany_bundesliga2",
};

// Einfrier-Fenster ums Kickoff: ab 30 Min vor bis 3 h nach Anstoß. Die
// erste passende Sync-Runde friert ein; danach wird nie überschrieben.
const FREEZE_BEFORE_MS = 30 * 60 * 1000;
const FREEZE_AFTER_MS = 3 * 60 * 60 * 1000;
const TWO_DAYS_MS = 2 * 24 * 60 * 60 * 1000;

const DIACRITICS: Record<string, string> = {
  "á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "ç": "c",
  "é": "e", "è": "e", "ê": "e", "ë": "e", "í": "i", "ì": "i", "î": "i",
  "ï": "i", "ñ": "n", "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
  "ú": "u", "ù": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y",
};

const WORLD_CUP: Record<string, string> = {
  "algeria": "DZA", "argentina": "ARG", "australia": "AUS", "austria": "AUT",
  "belgium": "BEL", "bosnia herzegovina": "BIH",
  "bosnia and herzegovina": "BIH", "brazil": "BRA", "canada": "CAN",
  "cape verde": "CPV", "cabo verde": "CPV", "colombia": "COL",
  "croatia": "HRV", "curacao": "CUW", "czech republic": "CZE",
  "czechia": "CZE", "dr congo": "COD", "congo dr": "COD",
  "democratic republic of congo": "COD", "ecuador": "ECU", "egypt": "EGY",
  "england": "ENG", "france": "FRA", "germany": "DEU", "ghana": "GHA",
  "haiti": "HTI", "iran": "IRN", "ir iran": "IRN", "iraq": "IRQ",
  "ivory coast": "CIV", "cote divoire": "CIV", "japan": "JPN",
  "jordan": "JOR", "mexico": "MEX", "morocco": "MAR", "netherlands": "NLD",
  "new zealand": "NZL", "norway": "NOR", "panama": "PAN", "paraguay": "PAR",
  "portugal": "PRT", "qatar": "QAT", "saudi arabia": "SAU", "scotland": "SCT",
  "senegal": "SEN", "south africa": "RSA", "south korea": "KOR",
  "korea republic": "KOR", "spain": "ESP", "sweden": "SWE",
  "switzerland": "CHE", "tunisia": "TUN", "turkey": "TUR", "turkiye": "TUR",
  "usa": "USA", "united states": "USA", "uruguay": "URY", "uzbekistan": "UZB",
};

function normalizeName(s: string): string {
  const folded = s.toLowerCase().split("").map((c) => DIACRITICS[c] ?? c).join("");
  return folded.replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ");
}

function codeFor(sportKey: string, oddsTeamName: string): string | null {
  const n = normalizeName(oddsTeamName);
  switch (sportKey) {
    case "soccer_fifa_world_cup":
      return WORLD_CUP[n] ?? null;
    case "soccer_germany_bundesliga":
      return BUNDESLIGA[n] ?? null;
    case "soccer_germany_bundesliga2":
      return BUNDESLIGA2[n] ?? null;
    default:
      return null;
  }
}

// the-odds-api-Name (normalisiert) → Sportmonks-Team-ID. Muss zum Client
// (lib/core/data/odds/odds_team_resolver.dart) passen.
const BUNDESLIGA: Record<string, string> = {
  "bayern munich": "503", "bayern munchen": "503", "fc bayern munchen": "503",
  "borussia dortmund": "68", "dortmund": "68",
  "rb leipzig": "277", "leipzig": "277",
  "bayer leverkusen": "3321", "bayer 04 leverkusen": "3321", "leverkusen": "3321",
  "eintracht frankfurt": "366", "frankfurt": "366",
  "vfb stuttgart": "3319", "stuttgart": "3319",
  "sc freiburg": "3543", "freiburg": "3543",
  "werder bremen": "82", "bremen": "82",
  "augsburg": "90", "fc augsburg": "90",
  "union berlin": "1079", "1 fc union berlin": "1079", "fc union berlin": "1079",
  "tsg hoffenheim": "2726", "hoffenheim": "2726", "1899 hoffenheim": "2726",
  "1 fc koln": "3320", "fc koln": "3320", "koln": "3320", "fc cologne": "3320",
  "cologne": "3320",
  "fsv mainz 05": "794", "mainz": "794", "mainz 05": "794", "1 fsv mainz 05": "794",
  "borussia monchengladbach": "683", "monchengladbach": "683", "gladbach": "683",
  "hamburger sv": "2708", "hamburg": "2708",
  "sc paderborn": "2642", "paderborn": "2642", "sc paderborn 07": "2642",
  "fc schalke 04": "67", "schalke 04": "67", "schalke": "67",
  "elversberg": "3588", "sv elversberg": "3588",
};

const BUNDESLIGA2: Record<string, string> = {
  "1 fc heidenheim": "2831", "heidenheim": "2831",
  "1 fc kaiserslautern": "1638", "kaiserslautern": "1638",
  "1 fc magdeburg": "3527", "magdeburg": "3527",
  "1 fc nurnberg": "956", "nurnberg": "956", "nuremberg": "956",
  "arminia bielefeld": "2927", "bielefeld": "2927", "dsc arminia bielefeld": "2927",
  "dynamo dresden": "1077", "dresden": "1077", "sg dynamo dresden": "1077",
  "eintracht braunschweig": "3565", "braunschweig": "3565",
  "fc energie cottbus": "3322", "energie cottbus": "3322", "cottbus": "3322",
  "fc st pauli": "353", "st pauli": "353",
  "greuther furth": "3431", "furth": "3431", "spvgg greuther furth": "3431",
  "hannover 96": "2554", "hannover": "2554", "hanover 96": "2554",
  "hertha berlin": "3317", "hertha bsc": "3317", "hertha": "3317",
  "holstein kiel": "3611", "kiel": "3611",
  "karlsruher sc": "3114", "karlsruhe": "3114",
  "sv darmstadt 98": "482", "darmstadt": "482", "darmstadt 98": "482",
  "vfl bochum": "999", "bochum": "999", "vfl bochum 1848": "999",
  "vfl osnabruck": "2872", "osnabruck": "2872",
  "vfl wolfsburg": "510", "wolfsburg": "510",
};

type OddsEvent = {
  homeTeam: string;
  awayTeam: string;
  commence: number;
  homeWin: number;
  draw: number;
  awayWin: number;
  bookmaker: string;
};

// deno-lint-ignore no-explicit-any
function parseOddsEvents(data: any): OddsEvent[] {
  const out: OddsEvent[] = [];
  for (const ev of (data ?? [])) {
    const home = ev.home_team, away = ev.away_team, commence = ev.commence_time;
    if (!home || !away || !commence) continue;
    for (const bm of (ev.bookmakers ?? [])) {
      let parsed: OddsEvent | null = null;
      for (const market of (bm.markets ?? [])) {
        if (market.key !== "h2h") continue;
        let h: number | undefined, d: number | undefined, a: number | undefined;
        for (const o of (market.outcomes ?? [])) {
          if (o.name === home) h = o.price;
          else if (o.name === away) a = o.price;
          else if (String(o.name).toLowerCase() === "draw") d = o.price;
        }
        if (h != null && d != null && a != null) {
          parsed = {
            homeTeam: home, awayTeam: away, commence: Date.parse(commence),
            homeWin: h, draw: d, awayWin: a,
            bookmaker: bm.title ?? "Buchmacher",
          };
          break;
        }
      }
      if (parsed) { out.push(parsed); break; }
    }
  }
  return out;
}

type Candidate = { id: string; kickoff: number; homeShort: string; awayShort: string };

// Odds-Kandidaten aus OpenLigaDB-Matches (homeShort = OpenLigaDB-shortName).
// deno-lint-ignore no-explicit-any
function olCandidates(matches: any[]): Candidate[] {
  // deno-lint-ignore no-explicit-any
  return matches.map((m: any) => ({
    id: `openligadb:${m.matchID}`,
    kickoff: Date.parse(m.matchDateTimeUTC),
    homeShort: m.team1?.shortName ?? m.team1?.teamName ?? "",
    awayShort: m.team2?.shortName ?? m.team2?.teamName ?? "",
  }));
}

// Odds-Kandidaten aus Sportmonks-Fixtures (homeShort = Sportmonks-Team-ID,
// passend zu codeFor → BUNDESLIGA/BUNDESLIGA2).
// deno-lint-ignore no-explicit-any
function smCandidates(fixtures: any[]): Candidate[] {
  // deno-lint-ignore no-explicit-any
  return fixtures.map((f: any) => {
    const parts = f.participants ?? [];
    // deno-lint-ignore no-explicit-any
    const home = parts.find((p: any) => p?.meta?.location === "home") ?? parts[0];
    // deno-lint-ignore no-explicit-any
    const away = parts.find((p: any) => p?.meta?.location === "away") ?? parts[1];
    return {
      id: `sportmonks:${f.id}`,
      kickoff: Date.parse(String(f.starting_at ?? "").replace(" ", "T") + "Z"),
      homeShort: home ? String(home.id) : "",
      awayShort: away ? String(away.id) : "",
    };
  });
}

// Sucht zur Begegnung die passende Quote (Code-Paar + Zeitfenster); dreht
// Heim/Auswärts, falls der Buchmacher die Teams anders herum führt.
function matchEvent(sportKey: string, c: Candidate, events: OddsEvent[]) {
  for (const e of events) {
    const oHome = codeFor(sportKey, e.homeTeam);
    const oAway = codeFor(sportKey, e.awayTeam);
    if (!oHome || !oAway) continue;
    if (Math.abs(c.kickoff - e.commence) >= TWO_DAYS_MS) continue;
    if (oHome === c.homeShort && oAway === c.awayShort) {
      return { home: e.homeWin, draw: e.draw, away: e.awayWin, bm: e.bookmaker };
    }
    if (oHome === c.awayShort && oAway === c.homeShort) {
      return { home: e.awayWin, draw: e.draw, away: e.homeWin, bm: e.bookmaker };
    }
  }
  return null;
}

// deno-lint-ignore no-explicit-any
async function freezeOdds(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  sportKey: string,
  allCandidates: Candidate[],
  now: Date,
): Promise<number> {
  const nowMs = now.getTime();
  // Nur Spiele im Einfrier-Fenster ums Kickoff.
  const candidates = allCandidates.filter((c) =>
    c.kickoff >= nowMs - FREEZE_AFTER_MS &&
    c.kickoff <= nowMs + FREEZE_BEFORE_MS &&
    c.homeShort && c.awayShort
  );
  if (candidates.length === 0) return 0;

  // Schon eingefrorene Spiele überspringen (nie überschreiben).
  const { data: existing } = await supabase
    .from("fixture_odds")
    .select("fixture_id")
    .in("fixture_id", candidates.map((c) => c.id));
  const frozen = new Set((existing ?? []).map((r: { fixture_id: string }) => r.fixture_id));
  const todo = candidates.filter((c) => !frozen.has(c.id));
  if (todo.length === 0) return 0;

  const apiKey = Deno.env.get("ODDS_API_KEY");
  if (!apiKey) return 0;
  const oddsRes = await fetch(
    `https://api.the-odds-api.com/v4/sports/${sportKey}/odds/?` +
      new URLSearchParams({
        apiKey, regions: "eu", markets: "h2h", oddsFormat: "decimal",
      }),
  );
  if (!oddsRes.ok) return 0;
  const events = parseOddsEvents(await oddsRes.json());

  const rows = [];
  for (const c of todo) {
    const m = matchEvent(sportKey, c, events);
    if (!m) continue;
    rows.push({
      fixture_id: c.id,
      home_win: m.home,
      draw: m.draw,
      away_win: m.away,
      bookmaker: m.bm,
    });
  }
  if (rows.length === 0) return 0;
  // ignoreDuplicates: bereits gefrorene Quoten bleiben unangetastet.
  await supabase.from("fixture_odds").upsert(rows, {
    onConflict: "fixture_id",
    ignoreDuplicates: true,
  });
  return rows.length;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  const hasSecret = !!secret && req.headers.get("x-sync-secret") === secret;

  // Neben dem Cron-Secret darf auch ein eingeloggter Nutzer den Sync
  // anstoßen (On-Demand): nötig, wenn ein in der App sichtbares Spiel
  // serverseitig noch nicht gespiegelt ist und ein Tipp darauf sonst am
  // Fremdschlüssel/der Deadline-RLS scheitert.
  let authedUser = false;
  if (!hasSecret) {
    const authHeader = req.headers.get("Authorization");
    if (authHeader?.startsWith("Bearer ")) {
      try {
        const userClient = createClient(
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_ANON_KEY")!,
          { global: { headers: { Authorization: authHeader } } },
        );
        const { data } = await userClient.auth.getUser();
        authedUser = !!data.user;
      } catch (_) { /* nicht autorisiert */ }
    }
  }

  if (!hasSecret && !authedUser) {
    return new Response("Forbidden", { status: 403 });
  }

  const now = new Date();
  const url = new URL(req.url);
  const seasonOverride = url.searchParams.get("season");

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const summary: Record<string, number | string> = {};

  // 1) Sportmonks-Ligen — je Liga fehlertolerant, damit ein Ausfall (Rate-Limit
  //    o. Ä.) die übrigen nicht blockiert.
  for (const { leagueId, key } of SM_LEAGUES) {
    const season = Number(seasonOverride ?? currentSeason(now));
    try {
      const fixtures = await smSeasonFixtures(key);
      const rows = fixtures.map((f) => smFixtureRow(f, leagueId, season));
      if (rows.length > 0) {
        const { error } = await supabase.from("fixtures").upsert(rows);
        if (error) throw new Error(error.message);
      }
      summary[leagueId] = rows.length;

      // Quoten zum Anstoß einfrieren (best effort — blockiert den Sync nicht).
      const sportKey = ODDS_SPORT[leagueId];
      if (sportKey) {
        try {
          summary[`${leagueId}_odds_frozen`] =
            await freezeOdds(supabase, sportKey, smCandidates(fixtures), now);
        } catch (_) {
          summary[`${leagueId}_odds_frozen`] = -1;
        }
      }
    } catch (e) {
      summary[leagueId] = `error: ${e}`;
    }
  }

  // 2) OpenLigaDB-Ligen (WM) — inkl. Quoten-Freeze.
  for (const { leagueId, providerKey, fixedSeason } of OL_LEAGUES) {
    const season = fixedSeason ?? Number(seasonOverride ?? currentSeason(now));
    const res = await fetch(
      `https://api.openligadb.de/getmatchdata/${providerKey}/${season}`,
    );
    if (!res.ok) {
      summary[leagueId] = `error: OpenLigaDB HTTP ${res.status}`;
      continue;
    }
    const matches = await res.json();
    // deno-lint-ignore no-explicit-any
    const rows = matches.map((m: any) => toFixtureRow(m, leagueId, season, now));
    const { error } = await supabase.from("fixtures").upsert(rows);
    if (error) {
      summary[leagueId] = `error: ${error.message}`;
      continue;
    }
    summary[leagueId] = rows.length;

    const sportKey = ODDS_SPORT[leagueId];
    if (sportKey) {
      try {
        summary[`${leagueId}_odds_frozen`] =
          await freezeOdds(supabase, sportKey, olCandidates(matches), now);
      } catch (_) {
        summary[`${leagueId}_odds_frozen`] = -1;
      }
    }
  }

  return new Response(JSON.stringify({ synced: summary }), {
    headers: { "content-type": "application/json" },
  });
});
