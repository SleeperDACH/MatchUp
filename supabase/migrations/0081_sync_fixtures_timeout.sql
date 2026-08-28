-- Spielplan-Sync: Zeitlimit hochsetzen und das Secret in den Vault holen.
--
-- Beim Anbinden der Live-Punkte (0080) fiel im Vorbeigehen auf, dass
-- `net._http_response` für den Spielplan-Sync durchgehend
--
--   timed_out = true, status_code = null
--
-- meldet — 37 Läufe in sechs Stunden, also **jeder einzelne**, und alle davon
-- in `cron.job_run_details` als „succeeded" verbucht. Der Job wurde vor 0077
-- angelegt und trägt deshalb den pg_net-Standard von 5000 ms; ein Lauf über
-- die Spielpläne mehrerer Wettbewerbe braucht länger.
--
-- Warum das trotzdem lange niemandem auffiel: pg_net kappt nur die Verbindung
-- des Aufrufers. Die Edge Function läuft in der Regel weiter und schreibt ihre
-- Zeilen — die Spiegelung war also meistens aktuell. Garantiert ist das
-- nicht, und genau darin liegt die Gefahr: Ein halb durchgelaufener Sync
-- hinterlässt einen Spielplan, dem man nicht ansieht, dass er halb ist. An
-- einem Spieltag hängt daran, ob eine Partie überhaupt als `live` erkannt wird
-- — und damit die komplette Live-Punkte-Kette aus 0080.
--
-- 60 Sekunden, dieselbe Größenordnung wie beim Stats-Sync. Zusätzlich kommt
-- das Secret aus dem Vault statt als Literal im `cron.job`-Eintrag zu stehen
-- (Muster aus 0076); dort war es für jeden lesbar, der die Tabelle sehen darf.

select cron.unschedule('sync-fixtures')
  where exists (select 1 from cron.job where jobname = 'sync-fixtures');

select cron.schedule(
  'sync-fixtures',
  '*/10 * * * *',
  $$
  select net.http_post(
    url := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/sync-fixtures',
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
