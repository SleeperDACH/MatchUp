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
  const finished = m.matchIsFinished === true;
  // deno-lint-ignore no-explicit-any
  const endResult = (m.matchResults ?? []).find((r: any) => r.resultTypeID === 2);
  const lastGoal = (m.goals ?? []).at(-1);
  const started = new Date(m.matchDateTimeUTC) <= now;

  let homeScore: number | null = null;
  let awayScore: number | null = null;
  if (finished && endResult) {
    homeScore = endResult.pointsTeam1;
    awayScore = endResult.pointsTeam2;
  } else if (started && lastGoal) {
    homeScore = lastGoal.scoreTeam1 ?? 0;
    awayScore = lastGoal.scoreTeam2 ?? 0;
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

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
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
  }

  return new Response(JSON.stringify({ synced: summary }), {
    headers: { "content-type": "application/json" },
  });
});
