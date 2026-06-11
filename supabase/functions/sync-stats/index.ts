// Stats-Sync: leitet Spieler-Leistungsdaten je Spieltag aus den kostenlosen
// OpenLigaDB-Matchdaten ab (Tore per Torschützen-Nachname, Zu-Null per
// Verein) und spiegelt sie in public.player_match_stats.
//
// Die Matching-Logik ist 1:1 zu RoundScoringService.computeStats in
// lib/features/fantasy/data/round_scoring_service.dart — bei Änderungen
// BEIDE anpassen (wie bei der Scoring-View ↔ tip_scoring.dart).
//
// OpenLigaDB liefert nur Tore + Endstand; Assists, Karten und Minuten
// bleiben 0/false, bis ein reicherer Feed dieselben Spalten füllt.
//
// Aufruf (Cron oder manuell):
//   POST /functions/v1/sync-stats             → aktuelle Saison
//   POST /functions/v1/sync-stats?season=2025 → bestimmte Saison
//
// Ohne JWT erreichbar (--no-verify-jwt), verlangt Header `x-sync-secret`
// (Secret SYNC_SECRET in den Function-Secrets).

import { createClient } from "npm:@supabase/supabase-js@2";

const PROVIDER_KEY = "bl1"; // Bundesliga; weitere Ligen analog ergänzbar

function currentSeason(now: Date): number {
  // Saison = Startjahr: ab Juli zählt das laufende Jahr (2025/26 → 2025).
  return now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1;
}

function lastName(name: string): string {
  const parts = name.trim().split(/\s+/);
  return parts.length === 0 ? "" : parts[parts.length - 1].toLowerCase();
}

// Markantestes Wort eines Vereinsnamens (längstes Token > 3 Zeichen) zum
// groben Abgleich (z. B. „bayern", „leverkusen").
function core(club: string): string {
  const tokens = club
    .toLowerCase()
    .replace(/[^a-zäöüß ]/g, "")
    .split(/\s+/)
    .filter((t) => t.length > 3);
  if (tokens.length === 0) return club.toLowerCase();
  tokens.sort((a, b) => b.length - a.length);
  return tokens[0];
}

type Player = { id: string; name: string; club: string; position: string };

// Roh-Stats eines Spieltags aus den (gefilterten) Matches dieses Spieltags.
// deno-lint-ignore no-explicit-any
function statsForRound(players: Player[], matches: any[]) {
  const goalsByLastName = new Map<string, number>();
  const cleanSheetClubs = new Set<string>();

  for (const m of matches) {
    if (m.matchIsFinished !== true) continue;
    const t1 = m.team1?.teamName ?? "";
    const t2 = m.team2?.teamName ?? "";
    // deno-lint-ignore no-explicit-any
    const end = (m.matchResults ?? []).find((r: any) => r.resultTypeID === 2);
    if (end) {
      const s1 = end.pointsTeam1 ?? 0;
      const s2 = end.pointsTeam2 ?? 0;
      if (s2 === 0) cleanSheetClubs.add(core(t1));
      if (s1 === 0) cleanSheetClubs.add(core(t2));
    }
    for (const g of m.goals ?? []) {
      const name: string | null = g.goalGetterName;
      if (!name || g.isOwnGoal === true) continue;
      const ln = lastName(name);
      if (!ln) continue;
      goalsByLastName.set(ln, (goalsByLastName.get(ln) ?? 0) + 1);
    }
  }

  const rows: Record<string, unknown>[] = [];
  for (const p of players) {
    const goals = goalsByLastName.get(lastName(p.name)) ?? 0;
    const cs =
      (p.position === "gk" || p.position === "def") &&
      cleanSheetClubs.has(core(p.club));
    if (goals === 0 && !cs) continue; // keine Daten -> kein Eintrag
    rows.push({
      player_id: p.id,
      goals,
      assists: 0,
      minutes: 0,
      yellow: 0,
      red: 0,
      clean_sheet: cs,
      appeared: goals > 0, // bestätigter Einsatz nur bei Torschütze
    });
  }
  return rows;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const now = new Date();
  const season = Number(
    new URL(req.url).searchParams.get("season") ?? currentSeason(now),
  );

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: players, error: poolErr } = await supabase
    .from("players")
    .select("id,name,club,position");
  if (poolErr) {
    return new Response(`Pool-Fehler: ${poolErr.message}`, { status: 500 });
  }

  const res = await fetch(
    `https://api.openligadb.de/getmatchdata/${PROVIDER_KEY}/${season}`,
  );
  if (!res.ok) {
    return new Response(`OpenLigaDB-Fehler: HTTP ${res.status}`, { status: 502 });
  }
  const matches = await res.json();

  // Matches nach Spieltag (groupOrderID) gruppieren.
  // deno-lint-ignore no-explicit-any
  const byRound = new Map<number, any[]>();
  // deno-lint-ignore no-explicit-any
  for (const m of matches as any[]) {
    const round = m.group?.groupOrderID ?? 0;
    if (!byRound.has(round)) byRound.set(round, []);
    byRound.get(round)!.push(m);
  }

  let upserted = 0;
  const rounds: number[] = [];
  for (const [round, group] of byRound) {
    const rows = statsForRound(players as Player[], group).map((r) => ({
      ...r,
      season,
      round,
      updated_at: new Date().toISOString(),
    }));
    if (rows.length === 0) continue;
    const { error } = await supabase
      .from("player_match_stats")
      .upsert(rows, { onConflict: "season,round,player_id" });
    if (error) {
      return new Response(
        `Upsert-Fehler (Spieltag ${round}): ${error.message}`,
        { status: 500 },
      );
    }
    upserted += rows.length;
    rounds.push(round);
  }

  return new Response(
    JSON.stringify({ season, rounds: rounds.sort((a, b) => a - b), upserted }),
    { headers: { "content-type": "application/json" } },
  );
});
