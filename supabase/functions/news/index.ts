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
};

// Stichwort-Filter, um aus einem allgemeinen Feed (kicker) themenpassende
// Meldungen zu ziehen.
const KEYWORDS: Record<string, RegExp> = {
  transfers: /transfer|wechsel|verpflicht|leih|abgang|zugang|unterschreib/i,
  injuries: /verletz|verletzt|sperre|gesperrt|ausfall|muskel|kreuzband|rote karte|op\b/i,
};

// Quellen je Thema: Google News (zielgenau) mit kicker-Fallback (allgemeiner
// Feed, per Stichwort gefiltert) — Google drosselt Cloud-IPs gelegentlich.
type Source = { url: string; filter?: RegExp };
function sources(topic: string): Source[] {
  return [
    {
      url: `https://news.google.com/rss/search?q=${encodeURIComponent(QUERIES[topic])}` +
        `&hl=de&gl=DE&ceid=DE:de`,
    },
    { url: "https://newsfeed.kicker.de/news/aktuell", filter: KEYWORDS[topic] },
  ];
}

const ttlMin = Number(Deno.env.get("NEWS_CACHE_TTL_MIN") ?? "30");
const MAX_ITEMS = 20;

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
function parseRss(xml: string, filter?: RegExp) {
  const items: Array<Record<string, string>> = [];
  const blocks = xml.match(/<item>([\s\S]*?)<\/item>/gi) ?? [];
  for (const block of blocks) {
    const rawTitle = decode(tag(block, "title") ?? "");
    const link = decode(tag(block, "link") ?? "");
    // Google News: <source>, Bing: <News:Source>.
    const source =
      decode(tag(block, "source") ?? tag(block, "News:Source") ?? "");
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
  if (!topic && req.method === "POST") {
    try {
      const body = await req.json();
      topic = body?.topic ?? "";
    } catch (_) {
      // kein/ungültiger Body
    }
  }
  if (!QUERIES[topic]) {
    return json({ error: "Unbekanntes oder fehlendes Thema." }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Frischen Cache-Eintrag direkt zurückgeben.
  const { data: cached } = await supabase
    .from("news_cache")
    .select("fetched_at, payload")
    .eq("topic", topic)
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
  let lastErr = "keine Quelle";
  outer:
  for (const src of sources(topic)) {
    // Pro Quelle bis zu zwei Versuche (Google 503 → kurzer Backoff).
    for (const wait of [0, 700]) {
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      try {
        const res = await fetch(src.url, { headers });
        if (!res.ok) {
          lastErr = `RSS ${res.status}`;
          continue;
        }
        const parsed = parseRss(await res.text(), src.filter);
        if (parsed.length > 0) {
          items = parsed;
          break outer;
        }
        lastErr = "leerer Feed";
        break; // Quelle erreichbar, aber nichts Passendes → nächste Quelle.
      } catch (e) {
        lastErr = `${e}`;
      }
    }
  }

  if (items.length === 0) {
    // Nichts frisch bekommen → lieber alten Cache als Fehler.
    if (cached) return json(cached.payload);
    return json({ error: `News-Abruf fehlgeschlagen: ${lastErr}` }, 502);
  }

  await supabase.from("news_cache").upsert({
    topic,
    fetched_at: new Date().toISOString(),
    payload: items,
  });
  return json(items);
});
