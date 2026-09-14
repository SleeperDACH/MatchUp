-- **Ein vergessenes --no-verify-jwt darf den Cron nicht mehr stilllegen.**
--
-- Gemeldet am 11.09.2026, mitten im Spiel: „Schalke gegen Union läuft seit
-- einer halben Stunde. Warum hat in der App immer noch keiner Punkte?" In
-- `player_match_stats` standen für Spieltag 3 null Zeilen, für die Spieltage 1
-- und 2 je rund 285.
--
-- Die Kette war intakt bis auf das Tor davor: Function ausgespielt, Cron aktiv
-- im Minutentakt, Sportmonks erreichbar, von Hand aufgerufen lieferte sie
-- sofort 23 Zeilen. In `net._http_response` standen **366 von 420** Antworten
-- auf 401 `UNAUTHORIZED_NO_AUTH_HEADER`. Beim Redeploy am 07.09. fehlte
-- `--no-verify-jwt`; seitdem wies das Gateway jeden Cron-Aufruf ab, bevor die
-- Function lief. Und `cron.job_run_details` meldete durchgehend „succeeded",
-- weil pg_net den Auftrag ja erfolgreich abgesetzt hat.
--
-- **Die Antwort darauf ist nicht, es künftig nicht zu vergessen.** Genau das
-- hatte die Konvention schon verlangt. Der Aufruf trägt jetzt einen
-- Authorization-Header, und damit kommt er **mit und ohne** die Flagge durch.
-- Nachgemessen am 11.09.: eine bewusst mit JWT-Prüfung ausgespielte Function
-- antwortet ohne Header 401 und mit diesem Header 403 — also aus ihrer eigenen
-- Secret-Prüfung heraus. Die Flagge ist damit eine Optimierung, keine
-- Voraussetzung mehr.
--
-- **Der Key steht hier im Klartext, und das ist Absicht.** `sb_publishable_…`
-- ist der von Supabase für den Client gedachte Schlüssel; er liegt ohnehin in
-- `AppConfig` und in jedem ausgelieferten Build. Ihn in den Vault zu legen
-- hieße, einen weiteren Einrichtungsschritt zu schaffen, den jemand vergessen
-- kann — und das ist genau der Fehler, den diese Migration behebt. Geschützt
-- wird der Aufruf weiterhin durch `x-sync-secret`, und der steht sehr wohl im
-- Vault.

do $$
declare
  v_key text := 'sb_publishable_lJBIlqeAYTILnQTInsK71Q_n2kCb7tN';
  v_job record;
  v_url text;
begin
  for v_job in
    select jobid, jobname, schedule, command
      from cron.job
     where command like '%functions/v1/%'
  loop
    -- Die URL aus dem bestehenden Kommando übernehmen, statt sie hier noch
    -- einmal aufzuschreiben: Sechs Kopien wären sechs Gelegenheiten, dass eine
    -- davon beim nächsten Mal nicht mitgezogen wird.
    v_url := substring(v_job.command from 'https://[^'']+');

    perform cron.schedule(
      v_job.jobname,
      v_job.schedule,
      format($cmd$
  select net.http_post(
    url := %L,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- **Der Grund für diese Zeile:** ohne sie weist das Gateway den Aufruf
      -- mit 401 ab, sobald eine Function ohne --no-verify-jwt ausgespielt
      -- wurde — und der Cron meldet trotzdem Erfolg.
      'Authorization', 'Bearer %s',
      'x-sync-secret',
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'sync_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := %s
  );
      $cmd$,
        v_url,
        v_key,
        coalesce(substring(v_job.command from 'timeout_milliseconds := (\d+)'), '60000')
      )
    );
  end loop;
end $$;


-- **Und eine Wache, die den Ausfall selbst bemerkt — nicht seine Ursache.**
--
-- Der Header oben schließt genau ein Loch. Die Wache fragt stattdessen nach
-- dem **Symptom**, das der Nutzer gemeldet hat: Ein Spiel läuft, und es gibt
-- keine Punkte. Das trifft auch den nächsten Ausfall, dessen Ursache heute
-- noch niemand kennt.
create table if not exists public.sync_stoerungen (
  id           bigserial primary key,
  erkannt_am   timestamptz not null default now(),
  art          text        not null,
  -- Ein Vorfall wird **einmal** festgehalten, nicht im Takt der Wache. Ohne
  -- das stünden hier je Spieltag hundert gleiche Zeilen und niemand läse sie.
  schluessel   text        not null,
  details      jsonb       not null default '{}'::jsonb,
  unique (art, schluessel)
);

alter table public.sync_stoerungen enable row level security;
-- Absichtlich ohne Policy: Das ist Betriebsprotokoll, kein App-Inhalt. Lesen
-- darf es der Service-Role-Key und wer per SQL drangeht.

comment on table public.sync_stoerungen is
  'Betriebsprotokoll der Sync-Wache. Überlebt die sechs Stunden, die pg_net '
  'seine Antworten aufhebt — genau daran ist die Ursachensuche am 11.09.2026 '
  'fast gescheitert.';

create or replace function public.pruefe_sync()
returns integer
language plpgsql
security definer
set search_path = public, net, pg_temp
as $$
declare
  v_neu integer := 0;
  v_f record;
  v_zeilen integer;
begin
  -- **Läuft ein Spiel länger als 20 Minuten ohne eine einzige Statistikzeile
  -- für seine Runde?** Zwanzig Minuten, weil die Quelle die erste Aufstellung
  -- nicht in der ersten Minute liefert — darunter wäre es ein Fehlalarm.
  for v_f in
    select id, round, home_name, away_name, kickoff
      from public.fixtures
     where league_id = 'bundesliga'
       and id like 'sportmonks:%'
       and status = 'live'
       and kickoff < now() - interval '20 minutes'
  loop
    select count(*) into v_zeilen
      from public.player_match_stats
     where season = extract(year from v_f.kickoff)::int
       and round = v_f.round;

    if v_zeilen = 0 then
      insert into public.sync_stoerungen (art, schluessel, details)
      values (
        'live_ohne_punkte',
        v_f.id,
        jsonb_build_object(
          'spiel', v_f.home_name || ' – ' || v_f.away_name,
          'runde', v_f.round,
          'anpfiff', v_f.kickoff
        )
      )
      on conflict (art, schluessel) do nothing;
      get diagnostics v_zeilen = row_count;
      v_neu := v_neu + v_zeilen;
    end if;
  end loop;

  -- **Und der breitere Fall:** Antworten unserer eigenen Aufrufe, die nicht
  -- im 2xx-Bereich liegen. Deckt auch ab, was außerhalb eines Spieltags
  -- kaputtgeht — und hält es fest, bevor pg_net die Zeile wegräumt.
  insert into public.sync_stoerungen (art, schluessel, details)
  select
    'http_' || r.status_code,
    to_char(date_trunc('hour', r.created), 'YYYY-MM-DD HH24') || ':' || r.status_code,
    jsonb_build_object(
      'status', r.status_code,
      'inhalt', left(coalesce(r.content, ''), 200),
      'zuletzt', max(r.created) over ()
    )
    from net._http_response r
   where r.created > now() - interval '15 minutes'
     and (r.status_code is null or r.status_code < 200 or r.status_code >= 300)
   limit 1
  on conflict (art, schluessel) do nothing;

  return v_neu;
end $$;

comment on function public.pruefe_sync() is
  'Sync-Wache: fragt nach dem Symptom („Spiel läuft, keine Punkte"), nicht '
  'nach einer bestimmten Ursache. Alle 10 Minuten per pg_cron.';

select cron.schedule(
  'sync-wache',
  '*/10 * * * *',
  $$select public.pruefe_sync();$$
);

-- Was gerade nicht stimmt, in einer Zeile lesbar.
create or replace view public.sync_wache as
  select art, schluessel, erkannt_am, details
    from public.sync_stoerungen
   where erkannt_am > now() - interval '7 days'
   order by erkannt_am desc;
