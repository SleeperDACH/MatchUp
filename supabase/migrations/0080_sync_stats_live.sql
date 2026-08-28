-- Live-Punkte: Der Stats-Sync bekommt Minutentakt, den Vault und ein Zeitlimit.
--
-- Ausgangslage am 28.08.2026, mitten im ersten Spiel der Saison:
-- `player_match_stats` war **leer**, obwohl `sync-stats` seit Juni deployed war
-- und alle 15 Minuten lief — 7545 Läufe, alle in `cron.job_run_details` als
-- „succeeded" verbucht. Die Wahrheit stand wie immer in `net._http_response`:
--
--   status_code = 200, content = {"season":2026,"rounds":[],"upserted":0}
--
-- Diese Antwortform gibt es im Repo gar nicht (dort: `{fixtures, upserted}`).
-- Deployed war also eine **ältere** Fassung, die über „Runden" lief und keine
-- fand; die fixture-basierte Fassung im Repo war nie ausgespielt worden.
-- Dieselbe Falle wie bei `sync-squads`: geschrieben, committet, dokumentiert —
-- und nie deployed. `supabase functions list` zeigt, was wirklich draußen ist.
--
-- Drei Änderungen am Job:
--
--  1. **Minutentakt statt 15 Minuten.** „Live" heißt live; alle 15 Minuten ist
--     für ein laufendes Spiel keine Anzeige, sondern ein Archiv. Das ist
--     billiger, als es klingt: Die Function fragt zuerst die **eigene**
--     `fixtures`-Spiegelung und kehrt ohne einen einzigen Sportmonks-Request
--     um, wenn gerade nichts läuft. API-Kosten entstehen nur im Spielfenster —
--     ein Bundesliga-Spieltag kostet so rund 90 Requests von 2000 am Tag.
--  2. **Das Secret kommt aus dem Vault.** Es stand als Literal im
--     `cron.job`-Eintrag und war damit für jeden lesbar, der die Tabelle sehen
--     darf. Dasselbe Muster wie 0076 — und es gehört ohnehin nicht in eine
--     Migration, das Repo ist öffentlich.
--  3. **`timeout_milliseconds`.** Ohne den Parameter gilt der pg_net-Standard
--     von 5000 ms. Bei einem einzelnen laufenden Spiel reicht das; an einem
--     vollen Samstag holt die Function bis zu 25 Fixtures in einem Rutsch und
--     wäre darüber. Der Abbruch wäre wieder unsichtbar — `cron.job_run_details`
--     meldete „succeeded". Siehe die ausführliche Begründung in 0077.
--
-- Voraussetzung (einmalig, steht schon aus 0076):
--   select vault.create_secret('<SYNC_SECRET>', 'sync_secret');

select cron.unschedule('sync-stats')
  where exists (select 1 from cron.job where jobname = 'sync-stats');

select cron.schedule(
  'sync-stats',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/sync-stats',
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
