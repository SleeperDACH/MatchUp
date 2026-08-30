// Stats-Sync: spiegelt die vollständigen Spieler-Roh-Stats aus Sportmonks nach
// public.player_match_stats.
//
// Vorher kam der Feed aus OpenLigaDB und konnte nur Tore und Zu-Null füllen —
// Assists, Karten und Minuten standen fest auf 0, und `appeared` war `goals > 0`,
// wer also nicht traf, galt als nicht eingesetzt. Die Punktevergabe
// (scoring/config/scoring.config.json) bewertet aber rund 25 Kategorien.
//
// Zwei Eigenschaften machen das hier billig:
//   * Die Fixture-IDs kommen aus public.fixtures (von sync-fixtures gespiegelt),
//     nicht von Sportmonks — das kostet keinen einzigen API-Request.
//   * /fixtures/multi/{ids} liefert bis zu 25 Spiele samt Lineups und
//     Ereignissen für **einen** Request (gemessen: `remaining` sinkt um 1, nicht
//     um 25). Ein voller Bundesliga-Spieltag ist damit 1 Request.
//
// Zuordnung Spieler: Sportmonks-`player_id` → `sportmonks:<id>` = players.id.
// Das frühere Raten über Nachnamen entfällt vollständig.
//
// Aufruf (Cron oder manuell):
//   POST /functions/v1/sync-stats                    → laufende + eben beendete
//   POST /functions/v1/sync-stats?season=2026&round=3 → ein bestimmter Spieltag
//   POST /functions/v1/sync-stats?hours=8             → Nachlauffenster ändern
//
// Ohne JWT erreichbar (--no-verify-jwt), verlangt Header `x-sync-secret`
// (Secret SYNC_SECRET in den Function-Secrets).

import { createClient } from "npm:@supabase/supabase-js@2";

const BASE = "https://api.sportmonks.com/v3/football";
// Sportmonks-WAF blockt ohne Browser-User-Agent mit 403.
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120 Safari/537.36";
const KEY = Deno.env.get("SPORTMONKS_API_KEY");

// Fantasy läuft bewusst nur auf der 1. Bundesliga (entschieden Juli 2026).
const FANTASY_LEAGUE = "bundesliga";

// Wie viele Fixtures pro Multi-Abruf. Sportmonks erlaubt mehr; 25 hält die
// Antwort (~250 kB je Spiel) im Rahmen dessen, was eine Edge Function bequem
// im Speicher hält.
const BATCH = 25;

// Sportmonks-Positions-ID des Torwarts (empirisch geprüft: 24 = GK,
// 25 = DEF, 26 = MID, 27 = FWD).
const POS_GK = 24;

// Ereignis-Typen (aus /v3/core/types, model_type = event).
const EV_OWNGOAL = 15;
const EV_PENALTY_GOAL = 16;
const EV_PENALTY_MISSED = 17;
const EV_YELLOW = 19;
const EV_RED = 20;
const EV_YELLOW_RED = 21;

/**
 * Sportmonks-`type.code` → internes Zählfeld. Portiert aus
 * scoring/src/mapping.ts — **beide müssen gleich bleiben**, sonst rechnet das
 * Scoring-Modul mit anderen Zahlen als der Feed liefert.
 *
 * Bewusst NICHT übernommen: `yellowcards`/`redcards`. Karten kommen unten aus
 * den Ereignissen, weil nur die zwischen glatt Rot und Gelb-Rot unterscheiden;
 * die Lineup-Statistik wirft beides zusammen und würde Gelb-Rot doppelt zählen.
 *
 * Zwei Codes sind bewusst so gewählt und nicht die naheliegenderen Nachbarn:
 *   `dispossessed` (nicht `possession-lost`) — „Ballverlust" meint den im
 *   Zweikampf verlorenen Ball, nicht jeden Fehlpass; bei −0,4 je Fall wäre
 *   `possession-lost` mit 20+ Fällen je Spiel ruinös.
 *   `blocked-shots` (nicht `shots-blocked`) — ersteres ist der vom Spieler
 *   geblockte gegnerische Schuss, letzteres sein eigener geblockter Schuss.
 */
const STAT_CODE_MAP: Record<string, string> = {
  "minutes-played": "minutes",
  "goals": "goals",
  "assists": "assists",
  "big-chances-created": "bigChancesCreated",
  "big-chances-missed": "bigChancesMissed",
  "key-passes": "keyPasses",
  // Gemessen an echten Partien: dieser Code liegt fuer jeden Spieler vor.
  // "successful-passes" (Typ 81) existiert im Katalog, kommt in den
  // Fixture-Details aber nicht an.
  "accurate-passes": "accuratePasses",
  "shots-on-target": "shotsOnTarget",
  "successful-dribbles": "successfulDribbles",
  // **`goals-conceded` und `goalkeeper-goals-conceded` sind zwei Zahlen, nicht
  // eine.** Sie stehen deshalb NICHT beide hier — die Schleife unten addiert
  // alles, was sie findet, und aus zwei Codes auf dasselbe Feld wurde eine
  // Summe. Aufgefallen an Daniel Heuer Fernandes: 2 Gegentore laut Quelle,
  // 1 laut Torwart-Zahl (das Eigentor zählt dort nicht mit) — bei uns stand 3.
  //
  // Betroffen war **jeder eingesetzte Torwart**: Gemessen an vier Spieltagen
  // tragen 132 Aufstellungszeilen beide Codes, 1421 nur `goals-conceded`
  // (Feldspieler) und 9 nur `goalkeeper-goals-conceded`. Die neun sind der
  // Grund, warum der zweite Code nicht einfach entfallen kann.
  //
  // Aufgelöst wird das unten in `eventsForFixture`: `goals-conceded` gewinnt,
  // der Torwart-Wert ist nur die Rückfallebene.
  "goals-conceded": "goalsConceded",
  "saves": "saves",
  "tackles-won": "tacklesWon",
  "interceptions": "interceptions",
  // Nicht dasselbe wie interceptions: ball-recovery ist rund viermal
  // haeufiger (Schnitt 2,9 gegen 0,8 je Spieler ab 60 Minuten).
  "ball-recovery": "ballRecovery",
  "clearances": "clearances",
  "blocked-shots": "blockedShots",
  "fouls": "fouls",
  "offsides": "offsides",
  "dispossessed": "possessionLost",
  "error-lead-to-goal": "errorsLeadToGoal",
  "rating": "rating",
};

type Events = Record<string, number> & { rating: number | null };

function emptyEvents(): Events {
  return {
    minutes: 0,
    goals: 0,
    penaltyGoals: 0,
    assists: 0,
    bigChancesCreated: 0,
    keyPasses: 0,
    accuratePasses: 0,
    shotsOnTarget: 0,
    successfulDribbles: 0,
    goalsConceded: 0,
    saves: 0,
    penaltiesSaved: 0,
    tacklesWon: 0,
    interceptions: 0,
    ballRecovery: 0,
    clearances: 0,
    blockedShots: 0,
    yellowCards: 0,
    secondYellowCards: 0,
    redCards: 0,
    ownGoals: 0,
    penaltiesMissed: 0,
    errorsLeadToGoal: 0,
    bigChancesMissed: 0,
    offsides: 0,
    fouls: 0,
    possessionLost: 0,
    rating: null,
  };
}

// deno-lint-ignore no-explicit-any
async function smGet(path: string): Promise<any> {
  const sep = path.includes("?") ? "&" : "?";
  const res = await fetch(`${BASE}${path}${sep}api_token=${KEY}`, {
    headers: { "User-Agent": UA, Accept: "application/json" },
  });
  if (res.status === 429) {
    throw new Error("Sportmonks-Ratelimit erreicht (HTTP 429)");
  }
  if (!res.ok) throw new Error(`Sportmonks HTTP ${res.status} für ${path}`);
  return await res.json();
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Baut je Spieler eines Spiels das Zählwerk aus Lineup-Statistiken und
 * Ereignissen.
 *
 * Aus den Ereignissen kommt nur, was in den Lineup-Statistiken **nicht** steht:
 * Elfmetertore, verschossene Elfmeter, Eigentore und die Karten. Alles andere
 * stammt aus `lineups.details`, sonst würde doppelt gezählt.
 */
// deno-lint-ignore no-explicit-any
function eventsForFixture(fixture: any): Map<number, Events> {
  const byPlayer = new Map<number, Events>();
  const get = (pid: number) => {
    let e = byPlayer.get(pid);
    if (!e) {
      e = emptyEvents();
      byPlayer.set(pid, e);
    }
    return e;
  };

  // Torhüter je Mannschaft merken — für den gehaltenen Elfmeter unten.
  const gkByTeam = new Map<number, number>();

  for (const lu of fixture.lineups ?? []) {
    const pid = lu.player_id as number | null;
    if (pid == null) continue;
    const ev = get(pid);
    // Die beiden Gegentor-Codes werden getrennt gesammelt und erst danach
    // aufgelöst — addieren wäre falsch, sie messen dasselbe zweimal.
    let gegentore: number | undefined;
    let gegentoreTw: number | undefined;
    for (const det of lu.details ?? []) {
      const code = det?.type?.code as string | undefined;
      const value = det?.data?.value;
      if (typeof value !== "number") continue;
      if (code === "goals-conceded") {
        gegentore = value;
        continue;
      }
      if (code === "goalkeeper-goals-conceded") {
        gegentoreTw = value;
        continue;
      }
      const field = code ? STAT_CODE_MAP[code] : undefined;
      if (!field) continue;
      if (field === "rating") ev.rating = value;
      else (ev[field] as number) += value;
    }
    // `goals-conceded` ist die vollständige Zahl (Eigentore eingeschlossen)
    // und gewinnt. Fehlt sie, tritt der Torwart-Wert ein.
    const konzediert = gegentore ?? gegentoreTw;
    if (typeof konzediert === "number") ev.goalsConceded += konzediert;
    if (lu.position_id === POS_GK && ev.minutes > 0) {
      gkByTeam.set(lu.team_id as number, pid);
    }
  }

  for (const e of fixture.events ?? []) {
    const pid = e.player_id as number | null;
    const type = e.type_id as number;
    if (pid == null) continue;
    switch (type) {
      case EV_PENALTY_GOAL:
        // `goals` aus der Lineup-Statistik enthält Elfmetertore bereits; hier
        // wird nur festgehalten, wie viele davon Elfmeter waren (die Wertung
        // zieht sie unten von den regulären Toren ab).
        get(pid).penaltyGoals += 1;
        break;
      case EV_PENALTY_MISSED: {
        get(pid).penaltiesMissed += 1;
        // Sportmonks kennt keinen Typ „gehaltener Elfmeter" — `missed_penalty`
        // umfasst gehalten, Pfosten und drüber gleichermaßen. Nach
        // Produktentscheidung bekommt der gegnerische Torwart die Punkte
        // trotzdem; das ist bewusst großzügig und in Teilen sachlich falsch.
        for (const [teamId, gk] of gkByTeam) {
          if (teamId !== e.participant_id) get(gk).penaltiesSaved += 1;
        }
        break;
      }
      case EV_OWNGOAL:
        get(pid).ownGoals += 1;
        break;
      case EV_YELLOW:
        get(pid).yellowCards += 1;
        break;
      case EV_YELLOW_RED:
        get(pid).secondYellowCards += 1;
        break;
      case EV_RED:
        get(pid).redCards += 1;
        break;
    }
  }

  return byPlayer;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }
  if (!KEY) {
    return new Response("SPORTMONKS_API_KEY nicht gesetzt.", { status: 500 });
  }

  const url = new URL(req.url);
  const seasonParam = url.searchParams.get("season");
  const roundParam = url.searchParams.get("round");
  // Nachlauffenster: beendete Spiele werden noch eine Weile mitgezogen, weil
  // Sportmonks Statistiken nach Abpfiff nachträglich korrigiert.
  const hours = Number(url.searchParams.get("hours") ?? 6);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 1) Welche Spiele? Aus der eigenen Spiegelung — kostet keinen API-Request.
  let q = supabase
    .from("fixtures")
    .select("id,season,round,status,kickoff")
    .eq("league_id", FANTASY_LEAGUE);
  if (roundParam) {
    q = q.eq("round", Number(roundParam));
    if (seasonParam) q = q.eq("season", Number(seasonParam));
  } else {
    const since = new Date(Date.now() - hours * 3600_000).toISOString();
    q = q.in("status", ["live", "finished"]).gte("kickoff", since);
  }
  const { data: fixtures, error: fxErr } = await q;
  if (fxErr) {
    return new Response(`Fixture-Fehler: ${fxErr.message}`, { status: 500 });
  }
  if (!fixtures || fixtures.length === 0) {
    return new Response(JSON.stringify({ fixtures: 0, upserted: 0 }), {
      headers: { "content-type": "application/json" },
    });
  }

  // 2) Nur Spieler aus dem Pool bekommen Zeilen — der Rest der Aufstellung ist
  //    für Fantasy bedeutungslos.
  const { data: pool, error: poolErr } = await supabase
    .from("players")
    .select("id");
  if (poolErr) {
    return new Response(`Pool-Fehler: ${poolErr.message}`, { status: 500 });
  }
  const poolIds = new Set((pool ?? []).map((p: { id: string }) => p.id));

  // Sportmonks-ID → unsere Fixture-Zeile (für season/round beim Upsert).
  const meta = new Map<string, { season: number; round: number }>();
  const smIds: string[] = [];
  for (const f of fixtures) {
    const raw = String(f.id);
    if (!raw.startsWith("sportmonks:")) continue; // Altbestand ignorieren
    const smId = raw.slice("sportmonks:".length);
    meta.set(smId, { season: f.season, round: f.round });
    smIds.push(smId);
  }

  const rows: Record<string, unknown>[] = [];
  const now = new Date().toISOString();
  let requests = 0;

  for (const batch of chunk(smIds, BATCH)) {
    const data = await smGet(
      `/fixtures/multi/${batch.join(",")}` +
        `?include=lineups.details.type;events`,
    );
    requests += 1;
    for (const fixture of data?.data ?? []) {
      const m = meta.get(String(fixture.id));
      if (!m) continue;
      for (const [pid, ev] of eventsForFixture(fixture)) {
        const playerId = `sportmonks:${pid}`;
        if (!poolIds.has(playerId)) continue;
        if (ev.minutes <= 0) continue; // nicht eingewechselt -> keine Zeile
        rows.push({
          season: m.season,
          round: m.round,
          player_id: playerId,
          // Bestand aus 0009
          goals: ev.goals,
          assists: ev.assists,
          minutes: ev.minutes,
          yellow: ev.yellowCards,
          red: ev.redCards,
          // Bequemlichkeits-Spiegel für den Altpfad. Maßgeblich ist
          // goals_conceded + minutes; die Schwelle steht in der
          // Scoring-Konfiguration, nicht hier.
          clean_sheet: ev.minutes >= 60 && ev.goalsConceded === 0,
          appeared: true,
          // Neu aus 0074
          penalty_goals: ev.penaltyGoals,
          big_chances_created: ev.bigChancesCreated,
          key_passes: ev.keyPasses,
          accurate_passes: ev.accuratePasses,
          shots_on_target: ev.shotsOnTarget,
          successful_dribbles: ev.successfulDribbles,
          goals_conceded: ev.goalsConceded,
          saves: ev.saves,
          penalties_saved: ev.penaltiesSaved,
          tackles_won: ev.tacklesWon,
          interceptions: ev.interceptions,
          ball_recovery: ev.ballRecovery,
          clearances: ev.clearances,
          blocked_shots: ev.blockedShots,
          second_yellow: ev.secondYellowCards,
          own_goals: ev.ownGoals,
          penalties_missed: ev.penaltiesMissed,
          errors_lead_to_goal: ev.errorsLeadToGoal,
          big_chances_missed: ev.bigChancesMissed,
          offsides: ev.offsides,
          fouls: ev.fouls,
          possession_lost: ev.possessionLost,
          rating: ev.rating,
          source: "sportmonks",
          updated_at: now,
        });
      }
    }
  }

  let upserted = 0;
  for (const part of chunk(rows, 500)) {
    const { error } = await supabase
      .from("player_match_stats")
      .upsert(part, { onConflict: "season,round,player_id" });
    if (error) {
      return new Response(`Upsert-Fehler: ${error.message}`, { status: 500 });
    }
    upserted += part.length;
  }

  return new Response(
    JSON.stringify({
      fixtures: smIds.length,
      sportmonksRequests: requests,
      upserted,
    }),
    { headers: { "content-type": "application/json" } },
  );
});
