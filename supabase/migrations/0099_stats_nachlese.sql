-- Eine Nachlese, die Stats nach dem Abpfiff korrigiert.
--
-- Anlass: Bei Daniel Heuer Fernandes standen 3 Gegentore statt 2. Die Ursache
-- war ein Zaehlfehler in `sync-stats` (zwei Sportmonks-Codes addierten in
-- dasselbe Feld) — aber die Frage dahinter bleibt: **Wer raeumt hinterher
-- auf?**
--
-- `sync-stats` laeuft jede Minute und sieht dabei nur Spiele, deren Anpfiff
-- hoechstens `hours` (Standard 6) zurueckliegt. Das deckt die Live-Wertung und
-- die ersten Stunden danach ab. Sportmonks korrigiert Statistiken aber auch
-- spaeter noch — eine nachtraeglich anerkannte Vorlage, ein umgewidmetes
-- Eigentor, eine berichtigte Minutenzahl. Was nach diesem Fenster kommt, hat
-- bisher **niemand mehr geholt**.
--
-- Die Nachlese ist deshalb derselbe Aufruf mit weiterem Rueckblick, nur
-- selten: einmal pro Stunde ueber 72 Stunden. Das deckt ein ganzes
-- Spieltagswochenende ab und kostet fast nichts — die Function fragt zuerst
-- die eigene Spiegelung, und ein voller Spieltag ist **ein** Sportmonks-
-- Request (der multi-Endpunkt nimmt 25 Spiele).
--
-- **Der Upsert macht die Reparatur von selbst**: `player_match_stats` hat den
-- Schluessel (season, round, player_id), eine korrigierte Zahl ueberschreibt
-- also die alte. Es braucht keinen eigenen Reparaturpfad.
--
-- timeout_milliseconds ist Pflicht (pg_net-Standard 5000 ms, und
-- `cron.job_run_details` meldet trotzdem „succeeded" — der Fehlschlag stuende
-- nur in `net._http_response`). Das Secret kommt aus dem Vault, weil das Repo
-- oeffentlich ist.

select cron.unschedule('sync-stats-nachlese')
  where exists (select 1 from cron.job where jobname = 'sync-stats-nachlese');

select cron.schedule(
  'sync-stats-nachlese',
  '23 * * * *',
  $$
  select net.http_post(
    url := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/sync-stats?hours=72',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret',
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'sync_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);
