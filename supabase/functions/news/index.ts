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

// Quellen je Thema. **Sie werden gemischt, nicht der Reihe nach probiert.**
//
// Bis zum 05.09.2026 war das eine Kette mit `break` bei der ersten Quelle, die
// etwas lieferte. Seit die Sportschau wegen der Bilder vorn steht, liefert die
// erste Quelle immer etwas — und kicker und Google kamen nie mehr vor.
// Gemeldet als „warum sind nur noch News von Sportschau da, wo sind die
// kicker-News?". Eine Rangfolge ist die richtige Antwort auf „welche Quelle
// nehmen wir, wenn eine ausfällt", und die falsche auf „was steht im Feed".
// **Bundesliga-Bezug.** Nur für allgemeine Fußball-Feeds gedacht, die nicht
// ohnehin auf die Liga zugeschnitten sind: Ohne ihn stünde im Transfer-Feed
// dieser App „Manchester City zahlt 145 Millionen" und „Woltemade zu Juventus"
// — beides gemessen am 05.09.2026 im Spiegel-Feed, beides für eine
// Bundesliga-App keine Meldung.
const BUNDESLIGA =
  /bundesliga|bayern|dortmund|leipzig|leverkusen|frankfurt|stuttgart|gladbach|wolfsburg|bremen|freiburg|hoffenheim|mainz|augsburg|union berlin|st\. pauli|heidenheim|hamburger sv|\bhsv\b|köln|schalke|hertha|nürnberg|kaiserslautern|paderborn|elversberg|karlsruher|hannover|bochum|düsseldorf|magdeburg|braunschweig|dfb-pokal/i;

// `filter` = Thema, `mussAuch` = zusätzliche Bedingung. Beide müssen greifen;
// ein einzelner Ausdruck könnte das „und" nicht ausdrücken.
type Source = {
  url: string;
  filter?: RegExp;
  mussAuch?: RegExp;
  source?: string;
};
function sources(topic: string): Source[] {
  return [
    // **Alle Quellen hier tragen Bilder — das ist die Auswahlregel**
    // (05.09.2026, auf Ansage: „verschiedene Quellen, aber nur welche, die
    // Bilder haben"). kicker und Google News sind deshalb aus den Themen-
    // Feeds raus: Ihr RSS liefert je Meldung kein Bild, und die Artikelseiten
    // von kicker antworten auf jeden automatisierten Abruf mit 403. Als
    // **Notnagel** stehen sie weiter unten — siehe `nurTextQuellen`.
    //
    // **Sportschau steht vorn, weil sie die Bilder trägt.** Der Feed der ARD
    // legt je Meldung ein 16:9-Bild in `content:encoded`; kicker und Google
    // liefern keines (gemessen 03.09. und wieder 05.09.2026: Sportschau 59
    // von 59 Meldungen mit Bild, kicker 0 von 20). Bei gleichem Zeitstempel
    // gewinnt deshalb die frühere Quelle.
    {
      url: "https://www.sportschau.de/fussball/bundesliga/index~rss2.xml",
      filter: KEYWORDS[topic],
      source: "Sportschau",
    },
    // **Zeit und n-tv als weitere Bildquellen** (05.09.2026). Beide sind
    // allgemeiner Sport, deshalb wie beim Spiegel [BUNDESLIGA] als zweite
    // Bedingung. Gemessen: Zeit 15 Meldungen mit 30 KB je Bild, n-tv 10 mit
    // 12 KB — beide in derselben Größenordnung wie die Sportschau.
    {
      url: "https://newsfeed.zeit.de/sport/index",
      filter: KEYWORDS[topic],
      mussAuch: BUNDESLIGA,
      source: "Zeit",
    },
    {
      url: "https://www.n-tv.de/sport/rss",
      filter: KEYWORDS[topic],
      mussAuch: BUNDESLIGA,
      source: "n-tv",
    },
    // **Zweite Quelle mit Bildern** (05.09.2026). Anlass: kicker liefert im
    // RSS keins, und seine Artikelseiten antworten auf jeden automatisierten
    // Abruf mit 403 — die Titelbilder von kicker.de sind also nicht zu holen,
    // ohne eine bewusste Sperre zu umgehen.
    //
    // **Warum Spiegel und nicht FAZ**, obwohl die FAZ einen reinen
    // Bundesliga-Feed hat (39 Meldungen, alle mit Bild): Ihre Bilder wiegen
    // **593 KB** je Stück, und die Größe steht fest in der URL — jeder
    // Umschreibversuch (halbe, drittel, viertel Kantenlänge bei gleichem
    // Seitenverhältnis) antwortet mit 403. Beim Spiegel sind es **18 KB**,
    // weniger als die 40 der Sportschau.
    //
    // Der Preis ist der Zuschnitt: Der Feed ist allgemeiner Fußball, nicht
    // Bundesliga — deshalb [BUNDESLIGA] als zweite Bedingung.
    {
      url: "https://www.spiegel.de/sport/fussball/index.rss",
      filter: KEYWORDS[topic],
      mussAuch: BUNDESLIGA,
      source: "Spiegel",
    },
  ];
}

/// **Der Notnagel: Quellen ohne Bild.**
///
/// Sie stehen nicht im Feed — gefragt werden sie nur, wenn die Bildquellen
/// zusammen **nichts** liefern. Eine Meldung ohne Bild ist besser als ein
/// leerer Nachrichtenbereich; sie ist nur nicht gut genug, um neben den
/// bebilderten zu stehen.
function nurTextQuellen(topic: string): Source[] {
  return [
    {
      url: "https://newsfeed.kicker.de/news/bundesliga",
      filter: KEYWORDS[topic],
      // kicker-Feed hat kein <source>-Element je Item → Default-Quelle.
      source: "kicker",
    },
    {
      url:
        `https://news.google.com/rss/search?q=${encodeURIComponent(QUERIES[topic])}` +
        `&hl=de&gl=DE&ceid=DE:de`,
    },
  ];
}

const ttlMin = Number(Deno.env.get("NEWS_CACHE_TTL_MIN") ?? "30");
const MAX_ITEMS = 20;

// Obergrenze der **gemischten** Liste. `MAX_ITEMS` gilt je Quelle; bei drei
// Quellen kämen sonst bis zu 60 Meldungen in den Cache und über die Leitung.
// Dreißig sind mehr als die zwanzig von früher und bleiben eine Größe, die
// man scrollen kann.
const MAX_GEMISCHT = 30;

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
// **Das Titelbild eines Items.** Vier Wege, in dieser Reihenfolge:
// `<enclosure url>`, `<media:content url>`, `<media:thumbnail url>` und das
// erste `<img src>` in `content:encoded`/`description`.
//
// **Gemessen am 03.09.2026:** kicker und Google News liefern **kein** Bild je
// Meldung (Google gar keines, kicker nur das Kanal-Logo). Der Sportschau-Feed
// legt es als `<img>` in `content:encoded` — deshalb steht er in `sources()`
// vorn, sonst gäbe es überhaupt keine Bilder.
function bild(block: string): string {
  const treffer = block.match(/<enclosure[^>]+url=["']([^"']+)["']/i) ??
    block.match(/<media:content[^>]+url=["']([^"']+)["']/i) ??
    block.match(/<media:thumbnail[^>]+url=["']([^"']+)["']/i) ??
    block.match(/<img[^>]+src=["']([^"']+)["']/i);
  let url = treffer ? decode(treffer[1]) : "";
  if (!/^https?:\/\//i.test(url)) return "";
  // Sportschau liefert 1920 Pixel breite Bilder (240 KB); auf einer Kachel von
  // 116 × 74 Punkten sind das ein paar hundert Kilobyte für nichts. 640 reicht
  // auch bei dreifacher Pixeldichte und wiegt 38 KB.
  //
  // **Die Breite ist nicht frei wählbar:** Der Bilddienst kennt nur bestimmte
  // Stufen. Gemessen am 03.09.2026 antworten 1920, 1280, 960, 640, 512, 384
  // und 320 mit 200 — **800 und 480 dagegen mit 400**. Der erste Versuch stand
  // auf 800, und die Liste zeigte lauter Ersatzflächen.
  url = url.replace(/([?&]width=)\d+/i, "$1640");
  return url;
}

function parseRss(
  xml: string,
  filter?: RegExp,
  defaultSource?: string,
  mussAuch?: RegExp,
) {
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
    if (mussAuch && !mussAuch.test(`${rawTitle} ${desc}`)) continue;
    let title = rawTitle;
    if (source && title.endsWith(` - ${source}`)) {
      title = title.slice(0, title.length - source.length - 3).trim();
    }
    items.push({
      title,
      url: link,
      source,
      publishedAt: pubDate ? new Date(pubDate).toISOString() : "",
      image: bild(block),
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
  let erreicht = 0;
  let lastErr = "keine Quelle";

  // **Alle Quellen holen und mischen.** Vorher brach die Schleife bei der
  // ersten ab, die etwas lieferte — seit die Sportschau vorn steht und
  // zuverlässig liefert, kam keine zweite Quelle mehr vor.
  async function holen(quellen: Source[]) {
    return await Promise.all(quellen.map(async (src) => {
      // Pro Quelle bis zu zwei Versuche (Google 503 → kurzer Backoff).
      for (const wait of [0, 700]) {
        if (wait > 0) await new Promise((r) => setTimeout(r, wait));
        try {
          const res = await fetch(src.url, { headers });
          if (!res.ok) {
            lastErr = `RSS ${res.status}`;
            continue;
          }
          return parseRss(
            await res.text(),
            src.filter,
            src.source,
            src.mussAuch,
          );
        } catch (e) {
          lastErr = `${e}`;
        }
      }
      return [] as Array<Record<string, string>>;
    }));
  }

  let proQuelle = await holen(feeds);

  // **Der Notnagel.** Liefern die Bildquellen zusammen nichts — Ausfall,
  // Umbau eines Feeds, ein Thema ohne Treffer —, wird auf kicker und Google
  // ausgewichen. Deren Meldungen tragen kein Bild und stehen deshalb nie
  // *neben* den bebilderten, sondern nur an ihrer Stelle: Ein leerer
  // Nachrichtenbereich wäre schlechter als eine Kachel mit Zeitungssymbol.
  if (QUERIES[topic] && proQuelle.every((l) => l.length === 0)) {
    proQuelle = await holen(nurTextQuellen(topic));
  }

  // Zusammenführen in Quellenreihenfolge: Bei einer Dublette gewinnt die
  // frühere Quelle, und das ist die Sportschau — also die mit dem Bild.
  const gesehen = new Set<string>();
  for (const liste of proQuelle) {
    if (liste.length > 0) erreicht++;
    for (const it of liste) {
      // **Dubletten laufen über den Titel, nicht über den Link.** Dieselbe
      // Meldung steht bei Google News unter einer Weiterleitungs-URL und beim
      // Verlag unter seiner eigenen; die Links sind also nie gleich, die
      // Überschriften praktisch immer. Verglichen wird ohne Satzzeichen und
      // Groß-/Kleinschreibung.
      const key = (it.title ?? "")
        .toLowerCase()
        .replace(/[^a-zäöüß0-9]+/g, " ")
        .trim();
      if (key.length === 0 || gesehen.has(key)) continue;
      gesehen.add(key);
      items.push(it);
    }
  }

  // Nach Datum, neueste zuerst. Ohne das stünden erst alle 59
  // Sportschau-Meldungen und danach die von kicker — also wieder keine
  // Mischung, nur eine längere Liste.
  items.sort((a, b) => {
    const ta = Date.parse(a.publishedAt ?? "");
    const tb = Date.parse(b.publishedAt ?? "");
    if (Number.isNaN(ta) && Number.isNaN(tb)) return 0;
    if (Number.isNaN(ta)) return 1;
    if (Number.isNaN(tb)) return -1;
    return tb - ta;
  });

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

  if (items.length > MAX_GEMISCHT) items = items.slice(0, MAX_GEMISCHT);

  if (items.length === 0) {
    // Nichts frisch bekommen → lieber alten Cache als Fehler.
    if (cached) return json(cached.payload);
    return json({ error: `News-Abruf fehlgeschlagen: ${lastErr}` }, 502);
  }

  // **Nur eine vollständige Mischung wird gecacht.** Hat nur eine von mehreren
  // Quellen geantwortet, ist die Liste dünn und einseitig — die 30 Minuten
  // festzuschreiben hieße, einen Ausfall zu konservieren. Der nächste Aufruf
  // versucht es dann neu.
  if (erreicht >= Math.min(2, feeds.length)) {
    await supabase.from("news_cache").upsert({
      topic: cacheKey,
      fetched_at: new Date().toISOString(),
      payload: items,
    });
  }
  return json(items);
});
