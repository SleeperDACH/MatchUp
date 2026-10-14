// Sportmonks-Proxy: hält den geheimen SPORTMONKS_API_KEY serverseitig und
// liefert dem Client normalisierte Fixtures/Tabellen/Spieldetails. Eine Abfrage
// versorgt alle Nutzer und wird in public.sportmonks_cache mit TTL gecacht.
//
// Aufruf (Client, via supabase.functions.invoke mit Anon/User-JWT):
//   POST /functions/v1/sportmonks
//   Body: { "kind": "seasonFixtures", "leagueKey": "82" }
//         { "kind": "squad",          "teamId": "503" }
//         { "kind": "standings",      "leagueKey": "82" }
//         { "kind": "fixture",        "fixtureId": "19734892" }
//         { "kind": "live" }   ← alle fünf Ligen, nur das Zeitfenster um jetzt
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

// Sportmonks hat **zwei getrennte Typ-Nummernkreise**, und sie überschneiden
// sich: im `event`-Kreis ist 15 ein Eigentor, im `statistic`-Kreis ist 83
// eine Rote Karte. Die Torjägerliste liegt im Statistik-Kreis, dort ist Tor
// = 208. Wer hier eine Zahl ändert, prüft sie vorher gegen
// `/v3/core/types/<id>` und schaut auf `model_type`.
const ST_GOAL_TOPSCORER = 208;

// TTL je Ressource (Sekunden).
//
// **Der Saison-Spielplan ist langlebig, die Spielstände kommen aus `live`.**
// Bis Oktober 2026 stand `seasonFixtures` auf 60 s, und jeder Ablauf holte die
// ganze Saison neu: 27 Seiten über die fünf Ligen. Gemessen am 07.08.2026 kam
// der Live-Tab damit auf ~1.300 Abrufe je Stunde — bei 2.000 erlaubten je
// Entity. Jetzt liefert **eine** Abfrage (`live`, alle fünf Ligen, nur die
// Tage um jetzt) die Stände, und `seasonFixtures` legt sie beim Ausliefern
// über den gemerkten Spielplan (`mitLiveStand`). Der Spielplan selbst ändert
// sich nur bei Verlegungen; eine halbe Stunde reicht.
const TTL = {
  seasonFixtures: 1800,
  // Bestimmt die Obergrenze an Abrufen, nicht die Zahl der Nutzer: höchstens
  // ein Abruf je 8 s = 450 je Stunde, egal wie viele zusehen.
  live: 8,
  standings: 300,
  fixture: 45,
  season: 21600,
  topscorers: 3600,
  // Die Stände kommen auch hier aus `live`.
  teamFixtures: 900,
  // Kader ändert sich nur bei Transfers — ein Tag reicht völlig.
  squad: 86400,
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

/// Ein Fehler von Sportmonks, mit Status — der Aufrufer unterscheidet
/// „zu viele Abrufe" (429) von allem anderen.
class SmFehler extends Error {
  constructor(
    readonly status: number,
    message: string,
    /// Bei 429: Sekunden, bis das Kontingent zurückgesetzt wird.
    readonly sperreSek: number | null = null,
  ) {
    super(message);
  }
}

// deno-lint-ignore no-explicit-any
async function smGet(path: string): Promise<any> {
  const sep = path.includes("?") ? "&" : "?";
  const res = await fetch(`${BASE}${path}${sep}api_token=${KEY}`, {
    headers: { "User-Agent": UA, Accept: "application/json" },
  });
  if (!res.ok) {
    let sperreSek: number | null = null;
    if (res.status === 429) {
      // Sportmonks nennt die Restzeit im Körper (`rate_limit`), manche
      // Antworten nur im Kopf.
      const body = await res.json().catch(() => null);
      const s = Number(
        body?.rate_limit?.resets_in_seconds ?? res.headers.get("retry-after"),
      );
      sperreSek = Number.isFinite(s) && s > 0 ? Math.min(s, 3600) : 300;
    }
    throw new SmFehler(
      res.status,
      `Sportmonks HTTP ${res.status} für ${path}`,
      sperreSek,
    );
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
// **Die laufende Spielminute.** `FixtureStatus` kennt nur scheduled/live/
// finished, und in dieser Datei stand lange, der Feed liefere keine Minute.
// Das war falsch: Sie steht in `periods`. Gemessen an Union gegen Schalke
// (11.09.2026) trägt die 1. Halbzeit `minutes: 47` (45 + 2 Nachspielzeit) und
// die 2. `minutes: 103` — also **die Zahl, die man anzeigt**, nicht die
// Nettospielzeit. Maßgeblich ist der Abschnitt mit `ticking: true`; läuft
// keiner, ist gerade Pause oder das Spiel steht still.
// deno-lint-ignore no-explicit-any
function spielminute(f: any): number | null {
  const laufend = (f.periods ?? []).find((p: any) => p.ticking === true);
  const m = laufend?.minutes;
  return typeof m === "number" ? m : null;
}

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
    // **Nur im Spieldetail gefüllt.** Die Listen (Live-Tab, Favoriten,
    // Vereinsseite) fragen `periods` gar nicht erst ab — der Include kostet
    // dort gemessen 17 % Nutzlast (143 auf 167 KB je Seite des
    // Saison-Spielplans) für eine Zahl, die nur die Spielübersicht zeigt.
    // Ohne `periods` liefert `spielminute` `null`, und das ist hier richtig.
    minute: spielminute(f),
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

// Zustände, in denen sich an einem Spiel nichts mehr ändert. Alles andere im
// Fenster um jetzt kann gerade laufen oder gleich anfangen.
const ENDSTAND = new Set([
  "FT", "AET", "FT_PEN", "AWARDED", "WALKOVER",
  "CANCELLED", "POSTPONED", "ABANDONED", "DELETED",
]);

// Wie weit um jetzt ein Spiel als „vielleicht live" gilt: vier Stunden
// zurück deckt ein Pokalspiel mit Verlängerung, Elfmeterschießen und
// Unterbrechung ab; nach vorn genügen Minuten (Anpfiff kommt über `live`).
const FENSTER_ZURUECK_MS = 4 * 3600 * 1000;
const FENSTER_VOR_MS = 15 * 60 * 1000;

/// **Die Spielstände aller fünf Ligen in einer Abfrage.** Statt je Liga die
/// ganze Saison zu holen, fragt `live` nur die Kalendertage um jetzt — ein
/// voller Samstag sind gemessen 18 Partien und 30 KB auf einer Seite
/// (17.10.2026). `/livescores` wäre die naheliegende Wahl, zeigt ein
/// beendetes Spiel aber nur eine Viertelstunde lang; danach bliebe ein
/// gemerkter Spielplan auf „läuft" stehen.
///
/// `/fixtures/between` nimmt nur ganze Tage (`Y-m-d`, gemessen: Uhrzeiten
/// werden mit 422 abgewiesen), in UTC wie alle Sportmonks-Zeiten.
async function liveFenster() {
  const now = Date.now();
  const tag = (ms: number) => new Date(ms).toISOString().slice(0, 10);
  const von = tag(now - FENSTER_ZURUECK_MS);
  const bis = tag(now + FENSTER_ZURUECK_MS);
  const ligen = [...ALLOWED_LEAGUES].join(",");
  // deno-lint-ignore no-explicit-any
  const all: any[] = [];
  for (let page = 1; page <= 4; page++) {
    const r = await smGet(
      `/fixtures/between/${von}/${bis}?filters=fixtureLeagues:${ligen}` +
        `&include=participants;scores;state;round;stage&per_page=50&page=${page}`,
    );
    for (const f of r?.data ?? []) {
      all.push({ ...normFixture(f), league_key: String(f.league_id) });
    }
    const pg = r?.pagination ?? r?.meta?.pagination;
    if (!pg?.has_more) break;
  }
  return { fixtures: all };
}

/// Ob ein gemerkter Spielplan Spiele enthält, deren Stand sich gerade ändern
/// kann. Nur dann lohnt es, `live` darüberzulegen.
// deno-lint-ignore no-explicit-any
function hatOffeneSpiele(fixtures: any[]): boolean {
  const now = Date.now();
  return fixtures.some((f) => {
    if (ENDSTAND.has(f.state)) return false;
    const t = Date.parse(f.starting_at ?? "");
    return Number.isFinite(t) &&
      t <= now + FENSTER_VOR_MS && t >= now - FENSTER_ZURUECK_MS;
  });
}

/// Legt die frischen Stände aus `live` über einen gemerkten Spielplan.
/// Ersetzt werden nur Stand, Zustand und Anstoß — alles, was die Liste
/// sonst trägt (bei `teamFixtures` etwa Wettbewerb und Logo), bleibt.
// deno-lint-ignore no-explicit-any
function mitLiveStand(fixtures: any[], live: any[]): any[] {
  const byId = new Map(live.map((f) => [f.id, f]));
  return fixtures.map((f) => {
    const l = byId.get(f.id);
    if (!l) return f;
    return {
      ...f,
      state: l.state,
      starting_at: l.starting_at ?? f.starting_at,
      home_score: l.home_score,
      away_score: l.away_score,
    };
  });
}

/// Kader eines Vereins. Läuft bei Sportmonks über die Entity `PlayerTeam` und
/// zehrt damit **nicht** am Fixture-Kontingent (eigenes Stundenlimit).
async function squad(teamId: string) {
  const r = await smGet(
    `/squads/teams/${teamId}?include=player.position;player.nationality`,
  );
  // deno-lint-ignore no-explicit-any
  const rows = ((r?.data ?? []) as any[]).map((s) => {
    const p = s.player ?? {};
    return {
      player_id: s.player_id,
      name: p.display_name ?? p.common_name ?? p.name ?? "?",
      // „Goalkeeper" / „Defender" / „Midfielder" / „Attacker" — die Zuordnung
      // auf die App-Positionen macht der Client, damit hier keine
      // Fantasy-Logik landet.
      position: p.position?.name ?? null,
      jersey_number: s.jersey_number ?? null,
      nationality: p.nationality?.name ?? null,
      date_of_birth: p.date_of_birth ?? null,
      image: p.image_path ?? null,
      captain: s.captain === true,
    };
  });
  // Trikotnummer aufsteigend, Spieler ohne Nummer ans Ende.
  rows.sort((a, b) => {
    const an = a.jersey_number ?? 9999;
    const bn = b.jersey_number ?? 9999;
    return an !== bn ? an - bn : String(a.name).localeCompare(String(b.name));
  });
  return { squad: rows };
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
      `?include=participants;scores;state;round;periods;events.type;venue;` +
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
  // Aufstellungen: Startelf (type 11) und Bank (type 12) je Team.
  //
  // **Nur die gemeldete Aufstellung, nie die Erwartung.** Gemeldet am
  // 12.09.2026: „Im Live-Tab sollen nur die offiziellen Aufstellungen
  // angezeigt werden, die circa 45 Minuten vor Anpfiff herausgegeben werden."
  // Sportmonks liefert Typ-11-Zeilen aber schon **Tage** vorher — gemessen am
  // 12.09. um 11 Uhr für Dortmund gegen Paderborn (Anpfiff 13:30): 22 Zeilen
  // Startelf, **null** Bank. Das ist dieselbe Vorhersage, die im
  // Fantasy-Bereich als „voraussichtlich" ausgewiesen wird; hier stand sie
  // ohne jeden Vorbehalt als Aufstellung da.
  //
  // **Erkannt wird die Meldung an der Bank, nicht an der Elf** — dieselbe
  // Regel, die `sync-predicted-lineups` seit dem 02.09. benutzt. Eine echte
  // Aufstellung bringt die Ersatzbank mit (gemessen an der gespielten Partie
  // Union gegen Schalke: 22 plus 18); eine Vorhersage kennt keine.
  //
  // **Je Mannschaft geprüft**, nicht je Partie: Meldet ein Verein früher als
  // der andere, soll seine Elf stehen und die andere Seite leer bleiben,
  // statt dass eine Vorhersage mit durchrutscht.
  // deno-lint-ignore no-explicit-any
  const alleZeilen = (f.lineups ?? []) as any[];
  const hatBank = (teamId: unknown) =>
    alleZeilen.some((l) => l.team_id === teamId && l.type_id === 12);

  const lineups = alleZeilen
    .filter((l) => hatBank(l.team_id))
    .map((l: any) => ({
      for_home: l.team_id === homeId,
      player_id: l.player_id ?? null,
      // **`display_name` zuerst, nicht `name`.** Sportmonks führt zwei Namen:
      // `name` ist der volle Registername, `display_name` der gebräuchliche.
      // Gemeldet: „Bei Grönbeak wird der falsche Name angezeigt, innerhalb von
      // Fantasy der richtige." Nachgemessen in derselben Antwort (HSV–Köln,
      // Fixture 19735165):
      //
      //   player.name   'Albert Grønbæk Erlykke'   ← stand im Live-Tab
      //   display_name  'Albert Grønbæk'           ← steht in Fantasy
      //   player_name   'Albert Grønbæk'
      //
      // Dasselbe bei David Mokwa („David Mokwa Ntusu"). Der Rückfall auf
      // `player_name` wäre richtig gewesen, kam aber nie zum Zug, weil
      // `player.name` immer gesetzt ist. Die Reihenfolge ist jetzt dieselbe
      // wie beim Kader-Weg oben und im Pool-Import
      // (`tools/import_sportmonks_pool.py`) — damit heißt ein Spieler in der
      // ganzen App gleich.
      name: l.player?.display_name ?? l.player_name ?? l.player?.name ?? "?",
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
      // Beim Wechsel ist `player` der Eingewechselte und `related` der
      // Ausgewechselte. Die ID dazu, damit der Client die beiden ohne
      // Namensabgleich in der Aufstellung findet.
      related_player_id: e.related_player_id ?? null,
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

// Torschützenliste (Statistik-Typ 208 = Tore) — ausschließlich die AKTUELLE
// Saison.
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

  // Der Filter muss mit, und zwar genau so: `seasonTopscorerTypes`.
  // `topscorerTypes` wird stillschweigend ignoriert (die Antwort sieht
  // trotzdem plausibel aus). Ohne Filter mischt die Antwort Karten, Tore und
  // Vorlagen in einer nach Typ gruppierten Liste — die Tore fangen erst auf
  // Seite 2 an, `per_page=25` sieht also ausschließlich Karten.
  const ts = await smGet(
    `/topscorers/seasons/${cs.id}?filters=seasonTopscorerTypes:${ST_GOAL_TOPSCORER}` +
      `&include=player;participant&per_page=25`,
  );
  // Zweite Sicherung: sollte der Filter serverseitig doch mal wegfallen,
  // liefert die Liste lieber nichts als Karten.
  // deno-lint-ignore no-explicit-any
  const goals = ((ts?.data ?? []) as any[]).filter(
    (t) => t.type_id === ST_GOAL_TOPSCORER,
  );
  if (goals.length === 0) return empty;

  goals.sort((a, b) => (a.position ?? 999) - (b.position ?? 999));
  return {
    season: cs.id,
    season_name: cs.name ?? null,
    current: true,
    scorers: goals.map((t) => ({
      position: t.position,
      goals: t.total,
      // Dieselbe Reihenfolge wie bei den Aufstellungen: der gebräuchliche
      // Name, nicht der volle Registername.
      player_name: t.player?.display_name ?? t.player?.name ?? "?",
      player_img: t.player?.image_path ?? null,
      team_name: t.participant?.name ?? null,
      team_img: teamImg(t.participant?.image_path),
    })),
  };
}

// --- Cache ---------------------------------------------------------------
/// Die gemerkte Zeile samt Alter — gleich, ob abgelaufen. Für den Rückfall
/// bei Störungen, wo eine alte Antwort besser ist als keine.
// deno-lint-ignore no-explicit-any
async function readCacheRow(supabase: any, key: string) {
  const { data } = await supabase
    .from("sportmonks_cache")
    .select("fetched_at, payload")
    .eq("cache_key", key)
    .maybeSingle();
  if (!data) return null;
  const ageSec = (Date.now() - new Date(data.fetched_at).getTime()) / 1000;
  // deno-lint-ignore no-explicit-any
  return { payload: data.payload as any, ageSec };
}
// deno-lint-ignore no-explicit-any
async function readCache(supabase: any, key: string, ttlSec: number) {
  const row = await readCacheRow(supabase, key);
  return row && row.ageSec < ttlSec ? row.payload : null;
}
// deno-lint-ignore no-explicit-any
async function writeCache(supabase: any, key: string, payload: unknown) {
  await supabase.from("sportmonks_cache").upsert({
    cache_key: key,
    fetched_at: new Date().toISOString(),
    payload,
  });
}

// **Eine leere Antwort wird nicht gemerkt** -- fuer die Listen, bei denen leer
// keine gueltige Auskunft ist.
//
// Ein Verein hat immer Spiele, eine Liga hat immer eine Tabelle. Kommt dort
// nichts, war es eine Stoerung; sie zwei Minuten festzuschreiben macht aus
// einer schlechten Antwort zwei Minuten schlechter Antworten -- fuer jeden,
// der in der Zeit hinsieht. Dieselbe Regel wie in der `news`-Function, wo nur
// eine vollstaendige Mischung in den Cache geht.
//
// **Nicht fuer alles.** `topscorers` darf leer sein: Der DFB-Pokal hat keine
// Torjaegerliste, und genau diese Zeile steht auch im Cache (gemessen
// 07.09.2026). Wer die Regel dorthin ausweitet, holt sie jedes Mal neu.
// deno-lint-ignore no-explicit-any
async function writeCacheWennGefuellt(
  supabase: any,
  key: string,
  payload: any,
  feld: string,
) {
  const liste = payload?.[feld];
  if (Array.isArray(liste) && liste.length === 0) return;
  await writeCache(supabase, key, payload);
}

// --- Ausliefern: Cache, Sperre, Rückfall ---------------------------------
// Welche Abfragen sich ein Sportmonks-Kontingent teilen. Das Stundenlimit
// gilt je Entity; Spielplan, Live-Stände und Spieldetail zählen alle auf
// „Fixture" (gemessen: `rate_limit.requested_entity`).
const KONTINGENT: Record<string, string> = {
  seasonFixtures: "fixture",
  live: "fixture",
  fixture: "fixture",
  teamFixtures: "fixture",
  standings: "standings",
  topscorers: "topscorers",
  squad: "squad",
};

/// **Nach einem 429 wird nicht weiter gefragt.** Jede weitere Anfrage im
/// gesperrten Zeitraum verlängert nichts und bringt nichts — sie verbrennt
/// nur die Antwortzeit des Nutzers. Die Sperre steht in derselben Tabelle
/// wie der Cache, damit alle Instanzen der Function sie sehen.
// deno-lint-ignore no-explicit-any
async function gesperrtBis(supabase: any, gruppe: string): Promise<number> {
  const row = await readCacheRow(supabase, `sperre:${gruppe}`);
  const bis = Date.parse(row?.payload?.bis ?? "");
  return Number.isFinite(bis) && bis > Date.now() ? bis : 0;
}

/// Liefert aus dem Cache, sonst frisch von Sportmonks — und wenn das
/// scheitert (429, 5xx, Netz), **die letzte gemerkte Antwort**, egal wie alt,
/// mit `stale: true`. Vorher gab es bei jeder Störung einen 502, und der
/// Live-Tab stand leer, obwohl der Spielplan von vor einer Minute noch dalag.
async function bediene(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: string,
  ck: string,
  ttl: number,
  // deno-lint-ignore no-explicit-any
  laden: () => Promise<any>,
  opts: { leerFeld?: string; nocache?: boolean } = {},
  // deno-lint-ignore no-explicit-any
): Promise<any> {
  if (!opts.nocache) {
    const cached = await readCache(supabase, ck, ttl);
    if (cached) return cached;
  }
  const gruppe = KONTINGENT[kind] ?? kind;
  try {
    const bis = await gesperrtBis(supabase, gruppe);
    if (bis) {
      throw new SmFehler(
        429,
        `Sportmonks-Kontingent erschöpft bis ${new Date(bis).toISOString()}`,
      );
    }
    const payload = await laden();
    if (opts.leerFeld) {
      await writeCacheWennGefuellt(supabase, ck, payload, opts.leerFeld);
    } else {
      await writeCache(supabase, ck, payload);
    }
    return payload;
  } catch (e) {
    if (e instanceof SmFehler && e.sperreSek) {
      await writeCache(supabase, `sperre:${gruppe}`, {
        bis: new Date(Date.now() + e.sperreSek * 1000).toISOString(),
      });
    }
    const alt = await readCacheRow(supabase, ck);
    if (alt) return { ...alt.payload, stale: true };
    throw e;
  }
}

/// Legt `live` über eine Spielplan-Antwort, wenn darin gerade etwas laufen
/// kann. Scheitert `live`, bleibt der Spielplan, wie er ist.
// deno-lint-ignore no-explicit-any
async function ueberlagert(supabase: any, payload: any) {
  const fixtures = payload?.fixtures;
  if (!Array.isArray(fixtures) || !hatOffeneSpiele(fixtures)) return payload;
  const live = await bediene(supabase, "live", "live", TTL.live, liveFenster)
    .catch(() => null);
  if (!Array.isArray(live?.fixtures)) return payload;
  return { ...payload, fixtures: mitLiveStand(fixtures, live.fixtures) };
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
  // `nocache` umgeht den Cache (Force-Refresh) — liest frisch, schreibt aber
  // weiter.
  const nocache = body.nocache === true;

  try {
    if (kind === "live") {
      return json(
        await bediene(supabase, "live", "live", TTL.live, liveFenster, {
          nocache,
        }),
      );
    }
    if (kind === "seasonFixtures" || kind === "standings") {
      if (!leagueKey || !ALLOWED_LEAGUES.has(leagueKey)) {
        return json({ error: "Unbekannte Liga." }, 400);
      }
      if (kind === "seasonFixtures") {
        const basis = await bediene(
          supabase,
          kind,
          `${kind}:${leagueKey}`,
          TTL.seasonFixtures,
          () => seasonFixtures(supabase, leagueKey),
          { leerFeld: "fixtures", nocache },
        );
        return json(await ueberlagert(supabase, basis));
      }
      return json(
        await bediene(
          supabase,
          kind,
          `${kind}:${leagueKey}`,
          TTL.standings,
          () => standings(supabase, leagueKey),
          { leerFeld: "standings", nocache },
        ),
      );
    }
    if (kind === "fixture") {
      if (!fixtureId) return json({ error: "fixtureId fehlt." }, 400);
      return json(
        await bediene(
          supabase,
          kind,
          `fixture:${fixtureId}`,
          TTL.fixture,
          () => fixtureDetail(fixtureId),
          { nocache },
        ),
      );
    }
    if (kind === "topscorers") {
      if (!leagueKey || !ALLOWED_LEAGUES.has(leagueKey)) {
        return json({ error: "Unbekannte Liga." }, 400);
      }
      return json(
        await bediene(
          supabase,
          kind,
          `topscorers:${leagueKey}`,
          TTL.topscorers,
          () => topScorers(leagueKey),
          { nocache },
        ),
      );
    }
    if (kind === "squad") {
      if (!teamId || !/^\d+$/.test(teamId)) {
        return json({ error: "Ungültige teamId." }, 400);
      }
      return json(
        await bediene(
          supabase,
          kind,
          `squad:${teamId}`,
          TTL.squad,
          () => squad(teamId),
          { nocache },
        ),
      );
    }
    if (kind === "teamFixtures") {
      if (!teamId || !/^\d+$/.test(teamId)) {
        return json({ error: "Ungültige teamId." }, 400);
      }
      const basis = await bediene(
        supabase,
        kind,
        `teamFixtures:${teamId}`,
        TTL.teamFixtures,
        () => teamFixtures(teamId),
        { leerFeld: "fixtures", nocache },
      );
      return json(await ueberlagert(supabase, basis));
    }
    return json({ error: "Unbekannter kind." }, 400);
  } catch (e) {
    return json({ error: String(e) }, 502);
  }
});
