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

// Später erweiterbar: weitere Ligen hier registrieren (analog zur
// Leagues-Registry in der App). Turniere haben ein festes Jahr
// (fixedSeason), Vereinsligen eine rollierende Saison.
const LEAGUES: { leagueId: string; providerKey: string; fixedSeason?: number }[] = [
  { leagueId: "bundesliga", providerKey: "bl1" },
  { leagueId: "wm2026", providerKey: "wm26", fixedSeason: 2026 },
];

function currentSeason(now: Date): number {
  // Saison = Startjahr: ab Juli zählt das laufende Jahr (2025/26 → 2025).
  return now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1;
}

// deno-lint-ignore no-explicit-any
function toFixtureRow(m: any, leagueId: string, season: number, now: Date) {
  // deno-lint-ignore no-explicit-any
  const endResult = (m.matchResults ?? []).find((r: any) => r.resultTypeID === 2);
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
  if (finished && endResult) {
    homeScore = endResult.pointsTeam1;
    awayScore = endResult.pointsTeam2;
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
  if (sportKey !== "soccer_fifa_world_cup") return null;
  return WORLD_CUP[normalizeName(oddsTeamName)] ?? null;
}

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
async function freezeOdds(supabase: any, sportKey: string, matches: any[], now: Date): Promise<number> {
  const nowMs = now.getTime();
  const candidates: Candidate[] = matches
    // deno-lint-ignore no-explicit-any
    .map((m: any) => ({
      id: `openligadb:${m.matchID}`,
      kickoff: Date.parse(m.matchDateTimeUTC),
      homeShort: m.team1?.shortName ?? m.team1?.teamName ?? "",
      awayShort: m.team2?.shortName ?? m.team2?.teamName ?? "",
    }))
    .filter((c: Candidate) =>
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

  const summary: Record<string, number> = {};
  for (const { leagueId, providerKey, fixedSeason } of LEAGUES) {
    const season =
      fixedSeason ?? Number(seasonOverride ?? currentSeason(now));
    const res = await fetch(
      `https://api.openligadb.de/getmatchdata/${providerKey}/${season}`,
    );
    if (!res.ok) {
      return new Response(
        `OpenLigaDB-Fehler für ${leagueId}: HTTP ${res.status}`,
        { status: 502 },
      );
    }
    const matches = await res.json();
    // deno-lint-ignore no-explicit-any
    const rows = matches.map((m: any) => toFixtureRow(m, leagueId, season, now));

    const { error } = await supabase.from("fixtures").upsert(rows);
    if (error) {
      return new Response(`Upsert-Fehler für ${leagueId}: ${error.message}`, {
        status: 500,
      });
    }
    summary[leagueId] = rows.length;

    // Quoten zum Anstoß einfrieren (best effort — blockiert den Sync nicht).
    const sportKey = ODDS_SPORT[leagueId];
    if (sportKey) {
      try {
        summary[`${leagueId}_odds_frozen`] =
          await freezeOdds(supabase, sportKey, matches, now);
      } catch (_) {
        summary[`${leagueId}_odds_frozen`] = -1;
      }
    }
  }

  return new Response(JSON.stringify({ synced: summary }), {
    headers: { "content-type": "application/json" },
  });
});
