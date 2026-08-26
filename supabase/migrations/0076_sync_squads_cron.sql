-- Kader-Sync planen: die Edge-Function `sync-squads` täglich aufrufen.
--
-- Warum es diese Migration überhaupt braucht: Die Function war geschrieben,
-- committet und dokumentiert — aber nie deployed und nie eingeplant. Der
-- Fantasy-Spielerpool stand deshalb monatelang auf dem Stand eines einmaligen
-- Hand-Imports (`tools/import_sportmonks_pool.py`): Zugänge fehlten, Abgänge
-- standen weiter drin. Ein Sync, den niemand auslöst, ist kein Sync.
--
-- Der Secret steht NICHT in dieser Datei — das Repo ist öffentlich. Er kommt
-- aus dem Supabase-Vault und muss dort einmalig liegen:
--
--   select vault.create_secret('<SYNC_SECRET>', 'sync_secret');
--
-- Fehlt er, legt diese Migration den Job trotzdem an; der Aufruf bekommt dann
-- 403 und der Pool bleibt stehen — sichtbar in `cron.job_run_details`.
--
-- Täglich um 04:17 UTC: außerhalb der Anstoßzeiten, und die krumme Minute
-- vermeidet, dass alle Jobs der Welt zur vollen Stunde gleichzeitig anlaufen.
-- Transfers sind kein Minutengeschäft — häufiger wäre nur API-Budget.

create extension if not exists pg_net with schema extensions;

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
    body := '{}'::jsonb
  );
  $$
);
