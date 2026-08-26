-- Kader-Sync: Zeitlimit des Aufrufs hochsetzen.
--
-- Migration 0076 hat den Job angelegt — und beim Nachmessen zeigte sich sofort,
-- dass er so nie sauber durchgelaufen wäre: `net.http_post` bricht nach
-- **5000 ms** ab (Standard von pg_net), ein vollständiger Kader-Lauf über 18
-- Vereine dauert aber rund 8 Sekunden. Der erste Testaufruf endete mit
--
--   timed_out = true
--   "Timeout of 5000 ms reached. Total time: 5000.766000 ms"
--
-- Das ist die unangenehmste Sorte Fehler: Der Job hätte jede Nacht gefeuert,
-- in `cron.job_run_details` stünde „succeeded" (pg_net setzt den Auftrag ja
-- erfolgreich ab), und ob die Function ihren Lauf zu Ende bringt, wenn der
-- Aufrufer die Verbindung kappt, ist nicht garantiert — ein halber Lauf
-- könnte Zugänge einspielen und das Entfernen der Abgänge auslassen. Genau
-- der Zustand, wegen dem der Pool schon einmal monatelang schief stand.
--
-- 120 Sekunden: großzügig gegenüber den gemessenen 8, und immer noch weit
-- unter dem, was die Function selbst maximal laufen darf.

select cron.unschedule('sync-squads')
  where exists (select 1 from cron.job where jobname = 'sync-squads');

select cron.schedule(
  'sync-squads',
  '17 4 * * *',
  $$
  select net.http_post(
    url := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/sync-squads',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret',
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'sync_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);
