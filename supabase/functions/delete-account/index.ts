// Löscht das Konto des aufrufenden Nutzers endgültig.
//
// Ablauf: Der JWT aus dem Authorization-Header identifiziert den Nutzer. Mit
// der Service-Role werden zuerst die Fremdschlüssel entschärft, die die
// profiles-Zeile blockieren würden (created_by/manager_id ohne ON DELETE
// CASCADE):
//   • Eigene Ligen/Tipprunden bleiben BESTEHEN — die Adminrechte (created_by)
//     gehen an das am längsten dabei seiende andere Mitglied über. Nur wenn es
//     keinen weiteren Teilnehmer gibt (Solo-Liga), wird sie gelöscht, weil
//     niemand sie übernehmen kann.
//   • Die verbleibenden Kader-/Draft-/Waiver-/Aufstellungs-Zeilen des
//     Ausscheidenden werden entfernt (er verlässt die Liga).
// Danach wird der Auth-User gelöscht; über profiles → ON DELETE CASCADE fällt
// der Rest weg (Favoriten, Freundschaften, Nachrichten, Mitgliedschaften,
// Tipps, Chat-Nachrichten …).

import { createClient } from "npm:@supabase/supabase-js@2";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "Nicht angemeldet." }, 401);
  }

  // Aufrufer über seinen JWT identifizieren.
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "Nicht angemeldet." }, 401);
  const uid = user.id;

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Übergibt die Adminrechte selbst erstellter Wettbewerbe an ein anderes
  // Mitglied, damit der Wettbewerb bestehen bleibt. Nur wenn niemand sonst
  // teilnimmt, wird er gelöscht (created_by ist NOT NULL — es gibt keinen
  // Besitzer mehr). Gibt Fehler nach oben weiter.
  async function handOverOrDelete(
    table: string,
    memberTable: string,
    fkColumn: string,
  ): Promise<void> {
    const { data: owned, error: ownedErr } = await admin
      .from(table)
      .select("id")
      .eq("created_by", uid);
    if (ownedErr) throw ownedErr;
    for (const row of owned ?? []) {
      const { data: heir, error: heirErr } = await admin
        .from(memberTable)
        .select("user_id")
        .eq(fkColumn, row.id)
        .neq("user_id", uid)
        .order("joined_at", { ascending: true })
        .limit(1)
        .maybeSingle();
      if (heirErr) throw heirErr;
      if (heir?.user_id) {
        const { error } = await admin
          .from(table)
          .update({ created_by: heir.user_id })
          .eq("id", row.id);
        if (error) throw error;
      } else {
        const { error } = await admin.from(table).delete().eq("id", row.id);
        if (error) throw error;
      }
    }
  }

  try {
    // Adminrechte an andere Mitglieder übergeben (Wettbewerbe bleiben bestehen).
    await handOverOrDelete("fantasy_leagues", "fantasy_league_members", "league_id");
    await handOverOrDelete("tip_rounds", "tip_round_members", "round_id");
    // Verbleibende eigene Zeilen in Ligen (blockieren sonst profiles-Löschung).
    for (const t of [
      "draft_picks",
      "fantasy_rosters",
      "fantasy_waiver_claims",
      "fantasy_lineups",
    ]) {
      const { error } = await admin.from(t).delete().eq("manager_id", uid);
      if (error) throw error;
    }
    // Auth-User löschen → profiles (ON DELETE CASCADE) räumt den Rest ab.
    const { error } = await admin.auth.admin.deleteUser(uid);
    if (error) throw error;
    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
