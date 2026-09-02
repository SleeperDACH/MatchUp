// Voraussichtliche Aufstellungen: spiegelt Sportmonks' `predictedLineups` nach
// public.predicted_lineups und die Formation nach public.predicted_formations.
//
// **Warum Sportmonks und nicht kicker:** Der Include steht im gebuchten Plan
// („Access Predicted Lineups"), liefert 11 Spieler je Mannschaft mit
// Rueckennummer und Formationsposition, und traegt dieselben Spieler-IDs wie
// unser Pool (`sportmonks:<id>` = players.id). Kicker gaebe dasselbe nur als
// HTML — mit Namensabgleich statt IDs, brechend bei jeder Layoutaenderung.
//
// **Gemessen am 29.08.2026: die Prognose steht erst 1-2 Tage vor Anpfiff.**
// Partien desselben und des naechsten Tages hatten je 22 Eintraege, der 02.09.
// (vier Tage) und der 05.09. (sieben Tage) keinen einzigen. Deshalb fragt der
// Sync nur das Fenster VORLAUF_TAGE ab; alles darueber hinaus waere ein
// Request fuer eine garantiert leere Antwort.
//
// **Die Bank kommt aus der gemeldeten Aufstellung, nicht aus der Prognose.**
// Gemessen am 02.09.2026: `predictedLineups` liefert genau elf Namen je
// Mannschaft, alle mit demselben type_id (111384) — eine vorhergesagte Bank
// gibt es nicht. Der Include `lineups` trennt dagegen type_id 11 (Startelf)
// von 12 (Bank) und kommt im selben multi-Request mit, ohne einen zweiten zu
// kosten. Fuer ein Spiel ohne gemeldete Aufstellung ist er leer. Also:
// **Was gemeldet ist, schlaegt was vorhergesagt ist** — sonst bleibt die
// Prognose stehen (Spalte `bestaetigt`, Migration 0118).
//
// Aufruf (Cron oder manuell):
//   POST /functions/v1/sync-predicted-lineups          → Fenster (Standard 3 Tage)
//   POST /functions/v1/sync-predicted-lineups?days=7   → Fenster aendern
//   POST /functions/v1/sync-predicted-lineups?fixture=sportmonks:19735196
//
// Ohne JWT erreichbar (--no-verify-jwt), verlangt Header `x-sync-secret`.

import { createClient } from "npm:@supabase/supabase-js@2";

const BASE = "https://api.sportmonks.com/v3/football";
// Sportmonks-WAF blockt ohne Browser-User-Agent mit 403.
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120 Safari/537.36";
const KEY = Deno.env.get("SPORTMONKS_API_KEY");

// Fantasy laeuft bewusst nur auf der 1. Bundesliga (entschieden Juli 2026) —
// aber der Spielplan im Profil zeigt auch den Pokal. Beide mitnehmen.
const LEAGUES = ["bundesliga", "dfb_pokal"];

// Wie weit im Voraus gefragt wird. Drei Tage decken den gemessenen Vorlauf mit
// Reserve ab.
const VORLAUF_TAGE = 3;

// Der multi-Endpunkt nimmt 25 Spiele fuer EINEN Request (gemessen: `remaining`
// sinkt um 1, nicht um 25).
const BATCH = 25;

function chunk<T>(xs: T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += n) out.push(xs.slice(i, i + n));
  return out;
}

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

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }
  if (!KEY) {
    return new Response("SPORTMONKS_API_KEY nicht gesetzt.", { status: 500 });
  }

  const url = new URL(req.url);
  const tage = Number(url.searchParams.get("days") ?? VORLAUF_TAGE);
  const nurFixture = url.searchParams.get("fixture");

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 1) Welche Spiele stehen an? Aus der eigenen Spiegelung — kostet keinen
  //    API-Request.
  let q = supabase
    .from("fixtures")
    .select("id,kickoff,status")
    .in("league_id", LEAGUES)
    .eq("status", "scheduled")
    .gte("kickoff", new Date(Date.now() - 3 * 3600_000).toISOString())
    .lte("kickoff", new Date(Date.now() + tage * 86400_000).toISOString());
  if (nurFixture) q = supabase
    .from("fixtures").select("id,kickoff,status").eq("id", nurFixture);

  const { data: fixtures, error } = await q;
  if (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }

  const smIds: string[] = [];
  for (const f of fixtures ?? []) {
    const raw = String(f.id);
    if (!raw.startsWith("sportmonks:")) continue; // Altbestand ignorieren
    smIds.push(raw.slice("sportmonks:".length));
  }
  if (smIds.length === 0) {
    return Response.json({ fixtures: 0, spieler: 0, requests: 0 });
  }

  let requests = 0;
  let spieler = 0;
  let mitPrognose = 0;
  let mitAufstellung = 0;

  for (const batch of chunk(smIds, BATCH)) {
    const data = await smGet(
      `/fixtures/multi/${batch.join(",")}?include=predictedLineups;formations;lineups`,
    );
    requests += 1;

    for (const fixture of data?.data ?? []) {
      const fixtureId = `sportmonks:${fixture.id}`;

      // Sportmonks' Typen: 11 = Startelf, 12 = Bank.
      //
      // **Erkannt wird die gemeldete Aufstellung an der Bank, nicht an der
      // Elf.** Gemessen am 02.09.2026: `lineups` trug fuer zwoelf
      // Mannschaften der Spieltage am 4. und 5.9. schon Zeilen vom Typ 11 —
      // zwei bis drei Tage vor Anpfiff, elf je Mannschaft und **ohne einen
      // einzigen** Typ 12. Das ist keine gemeldete Aufstellung, das ist
      // dieselbe Erwartung noch einmal. Eine echte Aufstellung bringt die
      // Ersatzbank mit (fuer die gespielte Partie: 22 plus 18).
      //
      // Wer hier nur auf Typ 11 prueft, schreibt „In der Startelf" ueber eine
      // Vermutung und stellt darunter eine leere Bank hin.
      const gemeldet = (fixture.lineups ?? []) as any[];
      const bestaetigt = gemeldet.some((p) => p.type_id === 12) &&
        gemeldet.some((p) => p.type_id === 11);
      const eintraege = bestaetigt ? gemeldet : (fixture.predictedlineups ?? []);

      // **Eine leere Antwort loescht nichts.** Sportmonks liefert die Prognose
      // erst kurz vor Anpfiff; ein Lauf davor wuerde sonst eine vorhandene
      // Elf wegraeumen, und das saehe in der App aus wie „Prognose
      // zurueckgezogen". Nur was tatsaechlich kommt, ersetzt den Stand.
      if (eintraege.length === 0) continue;
      mitPrognose += 1;
      if (bestaetigt) mitAufstellung += 1;

      // **Der Verein muss dazu, sonst findet die App die Zeile nicht.**
      // `predicted_lineups.fixture_id` traegt die Sportmonks-ID, die App
      // arbeitet aber mit OpenLigaDB-Spielplaenen — verbunden wird ueber
      // Verein und Spieltag (siehe 0092). In `fixtures` steht keine
      // Sportmonks-Team-ID, also loesen wir ueber den eigenen Pool auf:
      // Von elf vorhergesagten Spielern stehen praktisch immer mehrere in
      // `players`, und deren `club` ist der kanonische Name.
      const ids = eintraege.map((p: any) => `sportmonks:${p.player_id}`);
      const { data: bekannt } = await supabase
        .from("players")
        .select("id,club")
        .in("id", ids);
      const clubJeSpieler = new Map<string, string>(
        (bekannt ?? []).map((r: any) => [r.id, r.club]),
      );
      // Mehrheitsentscheid je Mannschaft — ein einzelner Spieler mit veraltetem
      // Vereinseintrag (Wechsel zwischen zwei Kader-Syncs) soll die ganze Elf
      // nicht in den falschen Verein schieben.
      const stimmen = new Map<number, Map<string, number>>();
      for (const p of eintraege) {
        const c = clubJeSpieler.get(`sportmonks:${p.player_id}`);
        if (!c) continue;
        const m = stimmen.get(p.team_id) ?? new Map<string, number>();
        m.set(c, (m.get(c) ?? 0) + 1);
        stimmen.set(p.team_id, m);
      }
      const clubJeTeam = new Map<number, string>();
      for (const [team, m] of stimmen) {
        let best: string | null = null;
        let max = 0;
        for (const [c, n] of m) if (n > max) { max = n; best = c; }
        if (best) clubJeTeam.set(team, best);
      }

      const zeilen = eintraege.map((p: any) => ({
        fixture_id: fixtureId,
        player_id: `sportmonks:${p.player_id}`,
        team_sm_id: p.team_id,
        club: clubJeTeam.get(p.team_id) ?? null,
        player_name: p.player_name ?? null,
        jersey_number: p.jersey_number ?? null,
        position_id: p.position_id ?? null,
        formation_position: p.formation_position ?? null,
        formation_field: p.formation_field ?? null,
        bank: bestaetigt && p.type_id === 12,
        bestaetigt,
        updated_at: new Date().toISOString(),
      }));

      // Ersetzen statt Ergaenzen: Wer aus der Elf gefallen ist, muss
      // verschwinden. Erst loeschen, was nicht mehr dabei ist, dann upserten —
      // in dieser Reihenfolge, damit zwischen beiden Schritten nie eine leere
      // Elf steht.
      const behalten = zeilen.map((z) => z.player_id);
      await supabase.from("predicted_lineups").upsert(zeilen, {
        onConflict: "fixture_id,player_id",
      });
      await supabase
        .from("predicted_lineups")
        .delete()
        .eq("fixture_id", fixtureId)
        .not("player_id", "in", `(${behalten.join(",")})`);
      spieler += zeilen.length;

      const formationen = (fixture.formations ?? []).map((f: any) => ({
        fixture_id: fixtureId,
        team_sm_id: f.participant_id,
        formation: f.formation ?? null,
        location: f.location ?? null,
        updated_at: new Date().toISOString(),
      }));
      if (formationen.length > 0) {
        await supabase.from("predicted_formations").upsert(formationen, {
          onConflict: "fixture_id,team_sm_id",
        });
      }
    }
  }

  return Response.json({
    fixtures: smIds.length,
    mitPrognose,
    mitAufstellung,
    spieler,
    requests,
  });
});
