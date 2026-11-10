-- Länderspiel-Details sichern (09.11.2026).
--
-- Die Edge Function `laenderspiel` holt Aufstellung, Karten und Wechsel der
-- Nationalmannschaft von API-Football. Der Gratis-Tarif kennt nur das
-- Datumsfenster gestern bis morgen — wer ein Länderspiel nicht am Spieltag
-- öffnet, käme danach nie mehr an die Details. Dieser Lauf holt deshalb nachts
-- die Endstände der Spiele der letzten 30 Stunden und merkt sie dauerhaft
-- (`sportmonks_cache`, Schlüssel `af:de:<Datum>`).
--
-- Welche Spiele das sind, sagt OpenLigaDB (`DFBN`): An Tagen ohne
-- Länderspiel kostet der Lauf keinen API-Football-Abruf.
--
-- 23:55 UTC (Abpfiff gegen 21:40 UTC) und 02:55 UTC als zweiter Versuch —
-- dann ist das Spiel „gestern" und liegt noch im Fenster.
--
-- Wie bei allen Crons seit 0125: Authorization-Header mit dem
-- Publishable-Key (kommt mit und ohne --no-verify-jwt durch), Secret aus dem
-- Vault, Zeitlimit gesetzt.

select cron.unschedule('laenderspiel-sammeln')
where exists (select 1 from cron.job where jobname = 'laenderspiel-sammeln');

select cron.schedule(
  'laenderspiel-sammeln',
  '55 2,23 * * *',
  $$
  select net.http_post(
    url := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/laenderspiel',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_lJBIlqeAYTILnQTInsK71Q_n2kCb7tN',
      'x-sync-secret',
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'sync_secret' limit 1)
    ),
    body := '{"sammeln": true}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);
