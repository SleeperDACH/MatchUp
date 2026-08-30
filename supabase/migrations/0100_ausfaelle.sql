-- Verletzungen und Sperren.
--
-- Die Daten lagen die ganze Zeit im gebuchten Plan, nur hatte sie nie jemand
-- geholt: `include=sidelined` auf Verein oder Spiel. Gemessen ueber die ganze
-- Liga (ein Request): **18 von 18 Vereinen liefern**, 98 offene Eintraege, 94
-- Verletzungen und 4 Sperren, davon 79 Spieler in unserem Pool. Die
-- Zuordnung laeuft ueber `sportmonks:<id>` = `players.id` — kein Namensraten.
--
-- Eine Zeile je Ausfall, nicht je Spieler: Ein Spieler kann gleichzeitig
-- gesperrt **und** verletzt sein (in den Messdaten kommt genau das vor).

create table if not exists public.player_absences (
  -- Die Sportmonks-ID des Ausfalls. Sie ist stabil, solange der Ausfall
  -- laeuft, und macht das Abgleichen trivial.
  id              bigint      primary key,
  player_id       text        not null references public.players(id) on delete cascade,
  -- 'injury' oder 'suspended' — so nennt es die Quelle, und so bleibt es hier.
  -- Uebersetzt wird erst in der Anzeige.
  kategorie       text        not null check (kategorie in ('injury','suspended')),
  type_id         int,
  seit            date,
  bis             date,
  spiele_verpasst int,
  updated_at      timestamptz not null default now()
);

create index if not exists player_absences_spieler_idx
  on public.player_absences (player_id);

-- Der Klartext zum `type_id`, einmal geholt und dann behalten.
--
-- **Ohne diese Tabelle kostet jeder Lauf 35 Requests** — es gibt keinen
-- Sammelabruf fuer Typen, nur `/core/types/<id>`. Mit ihr holt der Sync nur,
-- was er noch nicht kennt, also nach dem ersten Lauf praktisch nichts.
create table if not exists public.sideline_types (
  id   int  primary key,
  name text not null
);

alter table public.player_absences enable row level security;
alter table public.sideline_types  enable row level security;

drop policy if exists "Ausfaelle lesen" on public.player_absences;
create policy "Ausfaelle lesen" on public.player_absences
  for select to authenticated, anon using (true);

drop policy if exists "Ausfallgruende lesen" on public.sideline_types;
create policy "Ausfallgruende lesen" on public.sideline_types
  for select to authenticated, anon using (true);

-- Realtime: Eine Verletzung, die waehrend der Aufstellung bekannt wird, soll
-- ankommen, ohne dass jemand die App neu startet. Regel aus 0082:
-- Publication UND ein zuhoerender Provider.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime'
                   and tablename = 'player_absences') then
    alter publication supabase_realtime add table public.player_absences;
  end if;
end $$;

-- Stuendlich. Eine Verletzung meldet sich nicht im Minutentakt, und der Lauf
-- ist ein einziger Sportmonks-Request fuer die ganze Liga.
--
-- timeout_milliseconds ist Pflicht (pg_net-Standard 5000 ms, und
-- `cron.job_run_details` meldet trotzdem „succeeded"), das Secret kommt aus
-- dem Vault, weil das Repo oeffentlich ist.
select cron.unschedule('sync-absences')
  where exists (select 1 from cron.job where jobname = 'sync-absences');

select cron.schedule(
  'sync-absences',
  '41 * * * *',
  $$
  select net.http_post(
    url := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/sync-absences',
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
