// Versendet die offenen Aufträge aus `push_auftraege` über Firebase Cloud
// Messaging (HTTP v1).
//
// Aufruf (Cron jede Minute oder manuell):
//   POST /functions/v1/push
//
// Ohne JWT erreichbar (--no-verify-jwt), verlangt Header `x-sync-secret` —
// dieselbe Konvention wie die Sync-Functions.
//
// **Leerlauf kostet nichts.** Der erste Schritt ist die eigene Tabelle: Ist
// der Korb leer, kehrt die Function um, ohne Google auch nur anzusehen.
// Deshalb ist der Minutentakt vertretbar.
//
// **Warum HTTP v1 und nicht die alte Legacy-API:** Die Legacy-Schlüssel sind
// abgekündigt; v1 verlangt ein OAuth2-Token, das aus dem Dienstkonto-JSON
// entsteht (RS256-JWT → Token-Endpunkt). Das Token hält eine Stunde und wird
// hier im Modulzustand gehalten, solange die Instanz lebt — bei Minutentakt
// sind das rund 60 gesparte Token-Anfragen je Stunde.
//
// **Ungültige Tokens räumt der Versand selbst weg.** Wer die App löscht,
// hinterlässt einen Token, den FCM mit 404 `UNREGISTERED` quittiert. Die
// Zeile fliegt sofort raus; sonst wüchse die Tabelle mit jedem Deinstallieren
// und jeder Versand liefe dagegen.

import { createClient } from "npm:@supabase/supabase-js@2";

// Das Dienstkonto-JSON (Firebase-Konsole → Projekteinstellungen →
// Dienstkonten). Liegt als Supabase-Secret, nie im Repo:
//   supabase secrets set FIREBASE_DIENSTKONTO="$(cat ~/keys/firebase-dienstkonto.json)"
const DIENSTKONTO = Deno.env.get("FIREBASE_DIENSTKONTO");

// Wie viele Aufträge ein Lauf höchstens abarbeitet. Bei Minutentakt reicht
// das für 12.000 Nachrichten je Stunde; mehr würde nur das Zeitlimit reißen.
const PRO_LAUF = 200;

// Nach so vielen vergeblichen Anläufen gilt ein Auftrag als erledigt. Ohne
// diese Grenze zöge ein dauerhaft kaputter Auftrag jeden Lauf in die Länge.
const MAX_VERSUCHE = 5;

type Dienstkonto = {
  project_id: string;
  client_email: string;
  private_key: string;
};

let tokenCache: { token: string; gueltigBis: number } | null = null;

/// PEM (`-----BEGIN PRIVATE KEY-----`, Base64) zu rohem DER.
/// Gibt bewusst den ArrayBuffer zurueck: `crypto.subtle.importKey` verlangt
/// eine BufferSource, und ein `Uint8Array` fuehrt je nach TypeScript-Fassung
/// zu einem Typstreit ueber `ArrayBufferLike`.
function pemZuBytes(pem: string): ArrayBuffer {
  const roh = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(roh);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer as ArrayBuffer;
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// OAuth2-Zugriffstoken für FCM. Hält eine Stunde; wir erneuern fünf Minuten
/// früher, damit kein Lauf in die Lücke fällt.
async function zugriffstoken(k: Dienstkonto): Promise<string> {
  const jetzt = Math.floor(Date.now() / 1000);
  if (tokenCache && tokenCache.gueltigBis > jetzt + 300) return tokenCache.token;

  const kopf = { alg: "RS256", typ: "JWT" };
  const inhalt = {
    iss: k.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: jetzt,
    exp: jetzt + 3600,
  };
  const ungesigned = `${b64url(JSON.stringify(kopf))}.${b64url(JSON.stringify(inhalt))}`;

  const schluessel = await crypto.subtle.importKey(
    "pkcs8",
    pemZuBytes(k.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signatur = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      schluessel,
      new TextEncoder().encode(ungesigned),
    ),
  );
  const jwt = `${ungesigned}.${b64url(signatur)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`Token-Endpunkt HTTP ${res.status}: ${await res.text()}`);
  }
  const daten = await res.json();
  tokenCache = {
    token: daten.access_token,
    gueltigBis: jetzt + (daten.expires_in ?? 3600),
  };
  return tokenCache.token;
}

type Auftrag = {
  id: number;
  user_id: string;
  kategorie: string;
  titel: string;
  text: string;
  ziel: Record<string, unknown>;
  versuche: number;
};

/// Eine Nachricht an ein Gerät. Gibt zurück, ob der Token weg darf.
async function senden(
  projekt: string,
  token: string,
  geraeteToken: string,
  a: Auftrag,
): Promise<{ ok: boolean; wegwerfen: boolean; fehler?: string }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projekt}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: geraeteToken,
          notification: { title: a.titel, body: a.text },
          // Das Ziel reist als Daten mit — daraus baut die App beim Antippen
          // den passenden Schirm. Nur Strings: FCM lässt nichts anderes zu.
          data: {
            art: String(a.ziel?.art ?? ""),
            id: String(a.ziel?.id ?? ""),
            kategorie: a.kategorie,
          },
          // Kein `channel_id`: Der Kanal muesste in der App angelegt sein,
          // sonst zeigt Android 8+ die Benachrichtigung womoeglich gar nicht
          // an. Ohne Angabe nimmt das Firebase-SDK seinen Standardkanal.
          android: {
            priority: "HIGH",
            notification: { sound: "default" },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );

  if (res.ok) return { ok: true, wegwerfen: false };

  const text = await res.text();
  // 404 UNREGISTERED: App deinstalliert oder Token ersetzt.
  // 400 mit INVALID_ARGUMENT auf dem Token-Feld: Token ist Müll.
  const wegwerfen = res.status === 404 ||
    (res.status === 400 && text.includes("INVALID_ARGUMENT"));
  return { ok: false, wegwerfen, fehler: `HTTP ${res.status}: ${text.slice(0, 300)}` };
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Schritt eins ist immer die eigene Tabelle.
  const { data: auftraege, error } = await supabase
    .from("push_auftraege")
    .select("id, user_id, kategorie, titel, text, ziel, versuche")
    .is("gesendet_at", null)
    .lt("versuche", MAX_VERSUCHE)
    .order("erstellt_at", { ascending: true })
    .limit(PRO_LAUF);

  if (error) {
    return Response.json({ fehler: error.message }, { status: 500 });
  }
  if (!auftraege || auftraege.length === 0) {
    return Response.json({ auftraege: 0, gesendet: 0 });
  }

  if (!DIENSTKONTO) {
    return Response.json(
      { fehler: "FIREBASE_DIENSTKONTO nicht gesetzt." },
      { status: 500 },
    );
  }
  const konto: Dienstkonto = JSON.parse(DIENSTKONTO);
  const token = await zugriffstoken(konto);

  // Geräte aller betroffenen Nutzer in einem Rutsch.
  const nutzer = [...new Set(auftraege.map((a) => a.user_id))];
  const { data: geraete } = await supabase
    .from("push_geraete")
    .select("token, user_id")
    .in("user_id", nutzer);

  const proNutzer = new Map<string, string[]>();
  for (const g of geraete ?? []) {
    const liste = proNutzer.get(g.user_id) ?? [];
    liste.push(g.token);
    proNutzer.set(g.user_id, liste);
  }

  let gesendet = 0;
  let verworfen = 0;
  const muell: string[] = [];

  for (const a of auftraege as Auftrag[]) {
    const tokens = proNutzer.get(a.user_id) ?? [];
    if (tokens.length === 0) {
      // Kein Gerät mehr: Der Auftrag ist erledigt, nicht gescheitert.
      await supabase.from("push_auftraege")
        .update({ gesendet_at: new Date().toISOString(), fehler: "kein Gerät" })
        .eq("id", a.id);
      verworfen++;
      continue;
    }

    let einErfolg = false;
    let letzterFehler: string | undefined;

    for (const t of tokens) {
      const e = await senden(konto.project_id, token, t, a);
      if (e.ok) einErfolg = true;
      if (e.wegwerfen) muell.push(t);
      if (e.fehler) letzterFehler = e.fehler;
    }

    if (einErfolg) {
      await supabase.from("push_auftraege")
        .update({ gesendet_at: new Date().toISOString() })
        .eq("id", a.id);
      gesendet++;
    } else {
      // Nur der Zähler steigt — der nächste Lauf versucht es erneut, bis
      // MAX_VERSUCHE erreicht ist.
      await supabase.from("push_auftraege")
        .update({ versuche: a.versuche + 1, fehler: letzterFehler ?? null })
        .eq("id", a.id);
    }
  }

  if (muell.length > 0) {
    await supabase.from("push_geraete").delete().in("token", muell);
  }

  return Response.json({
    auftraege: auftraege.length,
    gesendet,
    verworfen,
    tokens_entfernt: muell.length,
  });
});
