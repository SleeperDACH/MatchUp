-- Ein Protokoll der Kaderbewegungen.
--
-- Anlass: Die Uebersicht soll einen Transfers-Bereich bekommen — eigene
-- Vorgaenge auf der einen Seite, die Bewegungen der ganzen Liga auf der
-- anderen. Fuer die zweite Seite gab es **keine Quelle**.
--
-- `fantasy_rosters` kennt nur den Bestand: `acquired_via` und `acquired_at`
-- sagen, wie und wann jemand in einen Kader kam. **Wer einen Kader verlaesst,
-- verschwindet spurlos** — die Zeile wird geloescht. Eine Liste „Kader-
-- Bewegungen" liesse sich daraus nur zur Haelfte bauen, und die fehlende
-- Haelfte ist genau die, die man sucht („wen hat er abgegeben?").
--
-- Deshalb ein eigenes Protokoll, gefuellt von einem **Trigger auf
-- `fantasy_rosters`** — dieselbe Begruendung wie beim Kaderlimit (0083) und
-- beim Aufstellungs-Aufraeumen (0094): Spieler kommen und gehen ueber ein
-- halbes Dutzend Funktionen, und der naechste Weg, den jemand baut, waere
-- sonst von vornherein nicht erfasst.

create table if not exists public.fantasy_roster_moves (
  id          bigserial primary key,
  league_id   uuid        not null references public.fantasy_leagues(id) on delete cascade,
  manager_id  uuid        not null,
  player_id   text        not null,
  -- 'zugang' oder 'abgang'. Ein Trade erzeugt beides: einen Abgang beim
  -- abgebenden und einen Zugang beim aufnehmenden Manager.
  richtung    text        not null check (richtung in ('zugang','abgang')),
  -- Woher der Zugang kam: draft | fa | waiver | trade. Beim Abgang bleibt es
  -- leer, ausser bei einem Trade — die Datenbank weiss beim Loeschen einer
  -- Kaderzeile nicht, ob ein Drop, eine Waiver-Abgabe oder eine
  -- Admin-Korrektur dahintersteckt, und **etwas zu raten waere schlimmer als
  -- nichts zu sagen**.
  weg         text,
  passiert_am timestamptz not null default now()
);

create index if not exists fantasy_roster_moves_liga_idx
  on public.fantasy_roster_moves (league_id, passiert_am desc);
create index if not exists fantasy_roster_moves_mgr_idx
  on public.fantasy_roster_moves (league_id, manager_id, passiert_am desc);

alter table public.fantasy_roster_moves enable row level security;

-- Lesen duerfen die Mitglieder der Liga. Geschrieben wird ausschliesslich vom
-- Trigger (security definer), nie vom Client.
drop policy if exists "Kaderbewegungen der eigenen Liga lesen"
  on public.fantasy_roster_moves;
create policy "Kaderbewegungen der eigenen Liga lesen"
  on public.fantasy_roster_moves for select
  to authenticated
  using (public.is_fantasy_member(league_id));

-- ---------------------------------------------------------------------------
-- Der Trigger
-- ---------------------------------------------------------------------------
create or replace function public.fantasy_bewegung_protokollieren()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if tg_op = 'INSERT' then
    insert into fantasy_roster_moves
      (league_id, manager_id, player_id, richtung, weg)
    values (new.league_id, new.manager_id, new.player_id, 'zugang',
            new.acquired_via);

  elsif tg_op = 'DELETE' then
    insert into fantasy_roster_moves
      (league_id, manager_id, player_id, richtung, weg)
    values (old.league_id, old.manager_id, old.player_id, 'abgang', null);

  elsif tg_op = 'UPDATE' and new.manager_id is distinct from old.manager_id then
    -- **Ein Trade ist zwei Bewegungen.** Er laeuft ueber ein `update` von
    -- `manager_id`, nicht ueber Delete+Insert; wer nur auf Delete hoert,
    -- sieht Trades gar nicht.
    insert into fantasy_roster_moves
      (league_id, manager_id, player_id, richtung, weg)
    values (old.league_id, old.manager_id, old.player_id, 'abgang', 'trade'),
           (new.league_id, new.manager_id, new.player_id, 'zugang', 'trade');
  end if;
  return null;
end$$;

drop trigger if exists fantasy_rosters_bewegung_protokollieren
  on public.fantasy_rosters;
create trigger fantasy_rosters_bewegung_protokollieren
  after insert or delete or update of manager_id on public.fantasy_rosters
  for each row
  execute function public.fantasy_bewegung_protokollieren();

-- ---------------------------------------------------------------------------
-- Rueckfuellung: die bekannten Zugaenge
-- ---------------------------------------------------------------------------
-- Damit die Liste nicht bei null anfaengt, kommen die Zugaenge aus dem
-- Bestand mit ihrem echten Zeitstempel hinein — Draft, Free Agency, Waiver und
-- die aufnehmende Seite jedes Trades.
--
-- **Abgaenge werden nicht erfunden.** Sie sind nirgends festgehalten; sie aus
-- dem Nichts zu rekonstruieren hiesse, Daten zu behaupten. Die Liste beginnt
-- fuer Abgaenge deshalb heute, und das ist ehrlicher als eine vollstaendig
-- aussehende Liste mit geratenen Eintraegen.
insert into public.fantasy_roster_moves
  (league_id, manager_id, player_id, richtung, weg, passiert_am)
select r.league_id, r.manager_id, r.player_id, 'zugang', r.acquired_via,
       r.acquired_at
  from public.fantasy_rosters r
 where not exists (
   select 1 from public.fantasy_roster_moves m
    where m.league_id = r.league_id and m.player_id = r.player_id
      and m.manager_id = r.manager_id and m.richtung = 'zugang');

-- Realtime: Wer den Transfers-Schirm offen hat, soll eine Bewegung sehen,
-- ohne die App neu zu starten. Regel aus 0082: Publication UND ein
-- zuhoerender Provider — eins allein reicht nicht.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'fantasy_roster_moves'
  ) then
    alter publication supabase_realtime add table public.fantasy_roster_moves;
  end if;
end $$;
