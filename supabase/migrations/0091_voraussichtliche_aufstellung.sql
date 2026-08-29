-- Voraussichtliche Aufstellungen: die erwartete Startelf je Spiel.
--
-- Anlass: Wer im Spielerprofil steht, will vor dem Aufstellen wissen, ob sein
-- Spieler ueberhaupt spielt. Die Frage stand bisher nirgends in der App.
--
-- **Quelle ist Sportmonks, nicht kicker.** Der Include `predictedLineups` ist
-- im gebuchten Plan enthalten („Access Predicted Lineups"), liefert 11 Spieler
-- je Mannschaft samt Rueckennummer und Formationsposition, und traegt dieselben
-- Spieler-IDs wie unser Pool (`sportmonks:<id>`). Kicker gaebe dasselbe nur als
-- HTML, mit Namensabgleich statt IDs, und mit einer ToS-Frage im Ruecken.
--
-- **Gemessen, nicht geschaetzt: die Prognose steht erst 1-2 Tage vor Anpfiff.**
-- Am 29.08.2026 lagen fuer die Partien desselben und des naechsten Tages je 22
-- Eintraege samt Formation vor, fuer den 02.09. (vier Tage) und den 05.09.
-- (sieben Tage) nichts. Daraus folgt zweierlei:
--   * Der Sync fragt nur Spiele im Fenster VORLAUF_TAGE an. Alles andere waere
--     ein Request fuer eine garantiert leere Antwort.
--   * Die App muss die Tage ohne Prognose als eigenen Zustand zeigen. Eine
--     leere Elf sieht sonst aus wie „niemand spielt" — derselbe Fehler wie beim
--     leeren Feld im Draft-Brett.
--
-- Die Zeilen sind fluechtig: Was Sportmonks meldet, ersetzt den Stand
-- vollstaendig (Loeschen + Einfuegen je Spiel in der Function), damit ein aus
-- der Elf gefallener Spieler nicht stehen bleibt.

create table if not exists public.predicted_lineups (
  fixture_id          text    not null references public.fixtures(id) on delete cascade,
  player_id           text    not null,
  team_sm_id          bigint  not null,
  player_name         text,
  jersey_number       int,
  -- Sportmonks mischt hier grobe und feine Positionen (24 Torwart, 27 Angriff,
  -- aber 148 Innenverteidiger, 153 Zentrales Mittelfeld). Deshalb roh
  -- gespeichert; gruppiert wird in der App nach players.position, die wir
  -- ohnehin haben und die zur Fantasy-Wertung passt.
  position_id         int,
  formation_position  int,
  formation_field     text,
  updated_at          timestamptz not null default now(),
  primary key (fixture_id, player_id)
);

create index if not exists predicted_lineups_fixture_idx
  on public.predicted_lineups (fixture_id);

-- Die Formation je Mannschaft ("3-4-2-1") kommt aus einem anderen Include und
-- haengt am Spiel, nicht am Spieler.
create table if not exists public.predicted_formations (
  fixture_id  text   not null references public.fixtures(id) on delete cascade,
  team_sm_id  bigint not null,
  formation   text,
  location    text,
  updated_at  timestamptz not null default now(),
  primary key (fixture_id, team_sm_id)
);

alter table public.predicted_lineups    enable row level security;
alter table public.predicted_formations enable row level security;

-- Lesen darf jeder Angemeldete, schreiben nur der Service-Role-Key (der die
-- RLS ohnehin umgeht). Dieselbe Regel wie bei fixtures und players: die Daten
-- sind oeffentlich, geschuetzt wird das Schreiben.
drop policy if exists "Aufstellungsprognose lesen" on public.predicted_lineups;
create policy "Aufstellungsprognose lesen"
  on public.predicted_lineups for select
  to authenticated, anon
  using (true);

drop policy if exists "Formationsprognose lesen" on public.predicted_formations;
create policy "Formationsprognose lesen"
  on public.predicted_formations for select
  to authenticated, anon
  using (true);

-- Realtime: Die Prognose aendert sich bis kurz vor Anpfiff mehrfach, und wer
-- das Profil offen hat, soll das sehen ohne die App neu zu starten. Regel aus
-- 0082: Publication UND ein zuhoerender Provider — eins allein reicht nicht.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'predicted_lineups'
  ) then
    alter publication supabase_realtime add table public.predicted_lineups;
  end if;
end $$;

-- Zeitplan: alle 30 Minuten. Die Prognose wechselt im Tagesrhythmus, nicht im
-- Minutentakt; ein voller Lauf ist ein einziger Sportmonks-Request (der
-- multi-Endpunkt nimmt 25 Spiele auf einmal, gemessen: `remaining` sinkt um 1).
--
-- timeout_milliseconds ist Pflicht, nicht Kosmetik: Der pg_net-Standard von
-- 5000 ms laeuft ab, und `cron.job_run_details` meldet trotzdem „succeeded" —
-- der Fehlschlag stuende nur in `net._http_response`. Genau daran lief
-- sync-fixtures monatelang in jedem Durchgang ins Limit (siehe 0081).
select cron.unschedule('sync-predicted-lineups')
  where exists (select 1 from cron.job where jobname = 'sync-predicted-lineups');

select cron.schedule(
  'sync-predicted-lineups',
  '*/30 * * * *',
  $$
  select net.http_post(
    url := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/sync-predicted-lineups',
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
