// Bundesliga-News-Proxy: holt einen öffentlichen Google-News-RSS-Feed zu
// Transfers bzw. Verletzungen/Sperren, parst die Schlagzeilen und cached sie
// in public.news_cache. Clients rufen nur diese Function (kein Key nötig, RSS
// ist frei syndizierbar). Eine Abfrage versorgt alle Nutzer und lädt den Feed
// nicht bei jedem App-Aufruf neu.
//
// Aufruf (vom Client via supabase.functions.invoke):
//   POST /functions/v1/news   Body: { "topic": "transfers" | "injuries" }

import { createClient } from "npm:@supabase/supabase-js@2";

// Google-News-RSS-Suchanfragen je Thema (deutsch, Deutschland).
const QUERIES: Record<string, string> = {
  transfers: "Bundesliga (Transfer OR Wechsel OR Verpflichtung) when:14d",
  injuries: "Bundesliga (Verletzung OR verletzt OR Sperre OR gesperrt OR Ausfall) when:14d",
  // Nur finalisierte Wechsel (Done Deals): Abschluss-Signalwörter.
  done_deals: "Bundesliga (Transfer OR Wechsel OR Verpflichtung) " +
    "(perfekt OR offiziell OR fix OR unterschreibt OR verpflichtet OR bestätigt) when:21d",
};

// Stichwort-Filter, um aus einem allgemeinen Feed (kicker) themenpassende
// Meldungen zu ziehen.
const KEYWORDS: Record<string, RegExp> = {
  transfers: /transfer|wechsel|verpflicht|leih|abgang|zugang|unterschreib/i,
  injuries: /verletz|verletzt|sperre|gesperrt|ausfall|muskel|kreuzband|rote karte|op\b/i,
  done_deals:
    /perfekt|offiziell|fix\b|unterschreib|verpflicht|wechselt (zu|zum|nach)|festgemacht|gebucht|best[äa]tigt/i,
};

// Quellen je Thema: Google News (zielgenau) mit kicker-Fallback (allgemeiner
// Feed, per Stichwort gefiltert) — Google drosselt Cloud-IPs gelegentlich.
type Source = { url: string; filter?: RegExp; source?: string };
function sources(topic: string): Source[] {
  return [
    {
      url: `https://news.google.com/rss/search?q=${encodeURIComponent(QUERIES[topic])}` +
        `&hl=de&gl=DE&ceid=DE:de`,
    },
    {
      url: "https://newsfeed.kicker.de/news/bundesliga",
      filter: KEYWORDS[topic],
      // kicker-Feed hat kein <source>-Element je Item → Default-Quelle.
      source: "kicker",
    },
  ];
}

const ttlMin = Number(Deno.env.get("NEWS_CACHE_TTL_MIN") ?? "30");
const MAX_ITEMS = 20;

// Liga-spezifische News: kicker-RSS je Liga (zuverlässig, kein Cloud-IP-Block).
// Frauen-Bundesliga hat keinen kicker-Feed → Google-News-Fallback (best effort).
const LEAGUE_FEED: Record<string, string> = {
  bundesliga: "https://newsfeed.kicker.de/news/bundesliga",
  bundesliga2: "https://newsfeed.kicker.de/news/2-bundesliga",
  liga3: "https://newsfeed.kicker.de/news/3-liga",
  dfb_pokal: "https://newsfeed.kicker.de/news/dfb-pokal",
};
const LEAGUE_NAME: Record<string, string> = {
  frauen_bundesliga: "Frauen-Bundesliga",
};

// kicker-Feeds mischen allgemeine/liga-fremde Transfer-News rein. Für eine
// saubere Liga-Zuordnung behalten wir nur Meldungen, deren Titel eine Liga
// bzw. einen ihrer Vereine nennt (Fallback: ungefiltert, damit nie leer).
const LEAGUE_KW: Record<string, string[]> = {
  bundesliga: [
    "bundesliga", "bayern", "dortmund", "bvb", "leipzig", "leverkusen",
    "frankfurt", "eintracht", "stuttgart", "vfb", "freiburg", "werder",
    "bremen", "augsburg", "union berlin", "hoffenheim", "köln", "koln",
    "mainz", "gladbach", "hamburg", "hsv", "paderborn", "schalke",
    "elversberg",
  ],
  bundesliga2: [
    "2. bundesliga", "zweite liga", "bielefeld", "arminia", "darmstadt",
    "dresden", "dynamo", "braunschweig", "cottbus", "energie", "hannover",
    "heidenheim", "hertha", "holstein", "kiel", "kaiserslautern", "lautern",
    "karlsruhe", "ksc", "magdeburg", "nürnberg", "nurnberg", "osnabrück",
    "osnabruck", "fürth", "furth", "st. pauli", "st pauli", "bochum",
    "wolfsburg",
  ],
  liga3: [
    "3. liga", "drittliga", "dritte liga", "hansa", "rostock", "ingolstadt",
    "havelse", "aue", "saarbrücken", "saarbrucken", "waldhof", "mannheim",
    "essen", "duisburg", "münster", "munster", "viktoria", "regensburg",
    "würzburg", "wurzburg", "verl", "aachen", "wiesbaden", "cottbus",
  ],
  dfb_pokal: ["pokal", "dfb-pokal", "dfb pokal"],
  frauen_bundesliga: ["frauen", "frauen-bundesliga"],
};

// Team-News: kicker-Team-RSS je Sportmonks-Team-ID (1./2. Bundesliga).
// Teams ohne Eintrag (z. B. Gladbach) fallen auf den nach Team-Namen
// gefilterten Liga-Feed zurück.
const TEAM_FEED: Record<string, string> = {
  "503": "fc-bayern-muenchen", "68": "borussia-dortmund", "277": "rb-leipzig",
  "3321": "bayer-04-leverkusen", "366": "eintracht-frankfurt",
  "3319": "vfb-stuttgart", "3543": "sc-freiburg", "82": "werder-bremen",
  "90": "fc-augsburg", "2726": "tsg-hoffenheim", "2708": "hamburger-sv",
  "1079": "1-fc-union-berlin", "3320": "1-fc-koeln", "794": "1-fsv-mainz-05",
  "2642": "sc-paderborn-07", "67": "fc-schalke-04", "3588": "sv-elversberg",
  "353": "fc-st-pauli", "482": "sv-darmstadt-98", "510": "vfl-wolfsburg",
  "956": "1-fc-nuernberg", "999": "vfl-bochum", "1077": "dynamo-dresden",
  "1638": "1-fc-kaiserslautern", "2554": "hannover-96", "2831": "1-fc-heidenheim",
  "2872": "vfl-osnabrueck", "2927": "arminia-bielefeld", "3114": "karlsruher-sc",
  "3317": "hertha-bsc", "3322": "energie-cottbus", "3431": "spvgg-greuther-fuerth",
  "3527": "1-fc-magdeburg", "3565": "eintracht-braunschweig",
  "3611": "holstein-kiel",
};

// Suchbegriffe für den Team-Fallback (Liga-Feed nach Team gefiltert): aus dem
// Namen abgeleitet + ein paar geläufige Kurzformen.
function teamKeywords(name: string): string[] {
  const folded = name.toLowerCase()
    .replaceAll("ä", "ae").replaceAll("ö", "oe").replaceAll("ü", "ue")
    .replaceAll("ß", "ss");
  const words = folded.split(/[^a-z0-9]+/).filter((w) => w.length > 3);
  const extra: string[] = [];
  if (folded.includes("gladbach")) extra.push("gladbach");
  return [...new Set([...words, name.toLowerCase(), ...extra])];
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Minimale HTML-/XML-Entity-Dekodierung für Titel/Quellen.
function decode(s: string): string {
  return s
    .replace(/<!\[CDATA\[(.*?)\]\]>/gs, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/<[^>]+>/g, "")
    .trim();
}

function tag(block: string, name: string): string | null {
  const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, "i"));
  return m ? m[1] : null;
}

// Parst RSS-<item>-Blöcke zu {title, url, source, publishedAt}. Google News
// hängt die Quelle als „ - Quelle" an den Titel; das trennen wir sauber ab.
// Mit [filter] werden nur Items behalten, deren Titel/Beschreibung passt.
function parseRss(xml: string, filter?: RegExp, defaultSource?: string) {
  const items: Array<Record<string, string>> = [];
  const blocks = xml.match(/<item>([\s\S]*?)<\/item>/gi) ?? [];
  for (const block of blocks) {
    const rawTitle = decode(tag(block, "title") ?? "");
    const link = decode(tag(block, "link") ?? "");
    // Google News: <source>, Bing: <News:Source>; sonst Default (z. B. kicker).
    const source =
      decode(tag(block, "source") ?? tag(block, "News:Source") ?? "") ||
      (defaultSource ?? "");
    const desc = decode(tag(block, "description") ?? "");
    const pubDate = (tag(block, "pubDate") ?? "").trim();
    if (!rawTitle || !link) continue;
    if (filter && !filter.test(`${rawTitle} ${desc}`)) continue;
    let title = rawTitle;
    if (source && title.endsWith(` - ${source}`)) {
      title = title.slice(0, title.length - source.length - 3).trim();
    }
    items.push({
      title,
      url: link,
      source,
      publishedAt: pubDate ? new Date(pubDate).toISOString() : "",
    });
    if (items.length >= MAX_ITEMS) break;
  }
  return items;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let topic = new URL(req.url).searchParams.get("topic") ?? "";
  let league = "";
  let team = "";
  let teamId = "";
  let nocache = false;
  if (req.method === "POST") {
    try {
      const body = await req.json();
      topic = topic || (body?.topic ?? "");
      league = body?.league ?? "";
      team = body?.team ?? "";
      teamId = body?.teamId ?? "";
      nocache = body?.nocache === true;
    } catch (_) {
      // kein/ungültiger Body
    }
  }

  // Team-News, liga-spezifische News oder ein Themen-Feed.
  let cacheKey: string;
  let feeds: Source[];
  // Team ohne eigenen kicker-Feed → Liga-Feed nach Team-Namen filtern.
  const teamFallback = !!teamId && !TEAM_FEED[teamId];
  if (teamId) {
    cacheKey = `team:${teamId}`;
    const slug = TEAM_FEED[teamId];
    if (slug) {
      feeds = [{ url: `https://newsfeed.kicker.de/team/${slug}`, source: "kicker" }];
    } else if (league && LEAGUE_FEED[league]) {
      feeds = [{ url: LEAGUE_FEED[league], source: "kicker" }];
    } else {
      return json([]); // keine Quelle
    }
  } else if (league) {
    // `league` = App-Liga-ID. kicker-Feed bevorzugt, sonst Google-News-Suche.
    cacheKey = `league:${league}`;
    const kicker = LEAGUE_FEED[league];
    if (kicker) {
      feeds = [{ url: kicker, source: "kicker" }];
    } else {
      const name = LEAGUE_NAME[league] ?? league;
      feeds = [{
        url: `https://news.google.com/rss/search?q=` +
          encodeURIComponent(`"${name}" Fußball when:14d`) +
          `&hl=de&gl=DE&ceid=DE:de`,
      }];
    }
  } else if (QUERIES[topic]) {
    cacheKey = topic;
    feeds = sources(topic);
  } else {
    return json({ error: "Unbekanntes oder fehlendes Thema." }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Frischen Cache-Eintrag direkt zurückgeben (außer bei Force-Refresh).
  const { data: cached } = nocache
    ? { data: null }
    : await supabase
      .from("news_cache")
      .select("fetched_at, payload")
      .eq("topic", cacheKey)
      .maybeSingle();

  if (cached) {
    const ageMin = (Date.now() - new Date(cached.fetched_at).getTime()) / 60000;
    if (ageMin < ttlMin) return json(cached.payload);
  }

  // Cache veraltet/leer → frisch holen. Google News drosselt Cloud-IPs
  // gelegentlich mit 503 → mehrere Versuche mit wachsendem Backoff.
  const headers = {
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    "Accept": "application/rss+xml, application/xml, text/xml, */*",
  };
  let items: Array<Record<string, string>> = [];
  let fromPrimary = false;
  let lastErr = "keine Quelle";
  outer:
  for (let i = 0; i < feeds.length; i++) {
    const src = feeds[i];
    // Pro Quelle bis zu zwei Versuche (Google 503 → kurzer Backoff).
    for (const wait of [0, 700]) {
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      try {
        const res = await fetch(src.url, { headers });
        if (!res.ok) {
          lastErr = `RSS ${res.status}`;
          continue;
        }
        const parsed = parseRss(await res.text(), src.filter, src.source);
        if (parsed.length > 0) {
          items = parsed;
          fromPrimary = i === 0;
          break outer;
        }
        lastErr = "leerer Feed";
        break; // Quelle erreichbar, aber nichts Passendes → nächste Quelle.
      } catch (e) {
        lastErr = `${e}`;
      }
    }
  }

  // Team-Fallback (Liga-Feed) nach Team-Namen filtern; Liga-Feeds nach Liga.
  // (Ein eigener kicker-Team-Feed ist bereits teamspezifisch → kein Filter.)
  const kw = teamFallback && team
      ? teamKeywords(team)
      : (!teamId && league ? LEAGUE_KW[league] : null);
  if (kw) {
    const filtered = items.filter((it) => {
      const t = (it.title ?? "").toLowerCase();
      return kw.some((k) => t.includes(k));
    });
    // Team-Fallback: nur echte Treffer (sonst leer, statt irreführender
    // Allgemein-News). Liga-Feeds: bei 0 Treffern ungefiltert lassen.
    if (teamFallback) {
      items = filtered;
    } else if (filtered.length > 0) {
      items = filtered;
    }
  }

  if (items.length === 0) {
    // Nichts frisch bekommen → lieber alten Cache als Fehler.
    if (cached) return json(cached.payload);
    return json({ error: `News-Abruf fehlgeschlagen: ${lastErr}` }, 502);
  }

  // Nur die Primärquelle (Google, zielgenau) cachen — der Fallback (kicker,
  // dünner) wird geliefert, aber nicht persistiert, damit der nächste Aufruf
  // wieder Google versucht und die Noise nicht 30 Min hängen bleibt.
  if (fromPrimary) {
    await supabase.from("news_cache").upsert({
      topic: cacheKey,
      fetched_at: new Date().toISOString(),
      payload: items,
    });
  }
  return json(items);
});
