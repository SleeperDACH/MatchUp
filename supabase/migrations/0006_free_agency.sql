-- Free Agency (Phase 4a): mutierbarer Kader, Drop und Direkt-Aufnahme.
--
-- Bisher war der Kader = Draft-Picks. Mit Free Agency ändert sich ein
-- Kader laufend (Drops, Aufnahmen), daher die eigene Tabelle
-- fantasy_rosters als Quelle der Wahrheit für den aktuellen Kader.
-- Draft-Picks befüllen sie per Trigger.
--
-- Regeln dieser Etappe:
-- * Kadergröße (ligaspezifisch) darf nie überschritten werden.
-- * Ab 05.09. (nach Transferschluss) sind U20-Spieler + Auslands-
--   Neuzugänge gesperrt (nicht per FA holbar) und für den U20-Draft
--   reserviert.
-- * Der U20-Draft kann erst nach Saisonende gestartet werden.
-- Die Waiver-Terminierung folgt in einer eigenen Migration.

-- ---------------------------------------------------------------------
-- Aktueller Kader
-- ---------------------------------------------------------------------
create table public.fantasy_rosters (
  league_id    uuid not null references public.fantasy_leagues (id) on delete cascade,
  manager_id   uuid not null references public.profiles (id),
  player_id    text not null references public.players (id),
  acquired_via text not null default 'draft' check (acquired_via in ('draft', 'fa', 'waiver')),
  acquired_at  timestamptz not null default now(),
  primary key (league_id, player_id)   -- ein Spieler je Liga nur in einem Kader
);

create index fantasy_rosters_mgr_idx
  on public.fantasy_rosters (league_id, manager_id);

alter table public.fantasy_rosters enable row level security;

create policy "Mitglieder sehen Kader"
  on public.fantasy_rosters for select
  using (public.is_fantasy_member(league_id));
-- Schreiben nur über die RPCs/den Trigger unten.

-- Draft-Pick -> Kadereintrag.
create function public.fantasy_roster_from_pick()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
  values (new.league_id, new.manager_id, new.player_id, 'draft')
  on conflict (league_id, player_id) do nothing;
  return new;
end$$;

create trigger draft_picks_to_roster
  after insert on public.draft_picks
  for each row execute function public.fantasy_roster_from_pick();

-- Bestehende Picks übernehmen.
insert into public.fantasy_rosters (league_id, manager_id, player_id, acquired_via)
  select league_id, manager_id, player_id, 'draft' from public.draft_picks
  on conflict do nothing;

alter publication supabase_realtime add table public.fantasy_rosters;

-- ---------------------------------------------------------------------
-- Sperren / Zeitpunkte
-- ---------------------------------------------------------------------

-- Ab 05.09. gesperrt: U20/Neuzugang und Transferfenster zu.
create function public.fantasy_is_locked(
  p_birth_date date, p_is_foreign boolean, p_season int, p_now timestamptz)
returns boolean language sql stable as $$
  select public.fantasy_is_rookie(p_birth_date, p_is_foreign, p_season)
     and p_now >= make_date(p_season, 9, 5);
$$;

-- Saisonende (Näherung: Mitte Mai des Folgejahres).
create function public.fantasy_season_over(p_season int, p_now timestamptz)
returns boolean language sql stable as $$
  select p_now >= make_date(p_season + 1, 5, 15);
$$;

-- ---------------------------------------------------------------------
-- Draft-Länge je Phase mit Kader-Obergrenze (Dynasty: Haupt-Draft lässt
-- Platz für den U20-Draft, Summe = Kadergröße).
-- ---------------------------------------------------------------------
create or replace function public.fantasy_advance(
  p_league_id uuid, p_manager uuid, p_player text, p_is_auto boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_p int; v_n int; v_squad int; v_total int; v_secs int;
  v_phase text; v_u20 int; v_mode text; v_rounds int;
begin
  select picks_made, draft_pick_seconds, public.fantasy_squad_size(roster),
         draft_phase, u20_rounds, mode
    into v_p, v_secs, v_squad, v_phase, v_u20, v_mode
    from fantasy_leagues where id = p_league_id;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;

  if v_phase = 'u20' then
    v_rounds := v_u20;
  elsif v_mode = 'dynasty' then
    v_rounds := v_squad - v_u20;     -- Platz für den U20-Draft lassen
  else
    v_rounds := v_squad;
  end if;
  v_total := v_n * v_rounds;

  insert into draft_picks (league_id, phase, pick_number, round, manager_id, player_id, is_auto)
  values (p_league_id, v_phase, v_p + 1, (v_p / v_n) + 1, p_manager, p_player, p_is_auto);

  if v_p + 1 >= v_total then
    update fantasy_leagues
      set picks_made = v_p + 1, current_pick_deadline = null, draft_status = 'done'
      where id = p_league_id;
  else
    update fantasy_leagues
      set picks_made = v_p + 1,
          current_pick_deadline = now() + (v_secs || ' seconds')::interval
      where id = p_league_id;
  end if;
end$$;

-- U20-Draft erst nach Saisonende.
create or replace function public.start_u20_draft(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_phase text; v_mode text; v_secs int; v_season int;
begin
  select created_by, draft_status, draft_phase, mode, draft_pick_seconds, season
    into v_created_by, v_status, v_phase, v_mode, v_secs, v_season
    from fantasy_leagues where id = p_league_id for update;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den U20-Draft starten';
  end if;
  if v_mode <> 'dynasty' then raise exception 'U20-Draft nur im Dynasty-Modus'; end if;
  if not (v_status = 'done' and v_phase = 'startup') then
    raise exception 'Der Haupt-Draft muss erst abgeschlossen sein';
  end if;
  if not public.fantasy_season_over(v_season, now()) then
    raise exception 'Der U20-Draft kann erst nach Saisonende gestartet werden';
  end if;

  update fantasy_leagues
    set draft_phase = 'u20', draft_status = 'drafting',
        picks_made = 0,
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;

-- ---------------------------------------------------------------------
-- Free Agency: Drop und (Direkt-)Aufnahme
-- ---------------------------------------------------------------------
create function public.fantasy_drop_player(p_league_id uuid, p_player_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from fantasy_rosters
                 where league_id = p_league_id and player_id = p_player_id
                   and manager_id = auth.uid()) then
    raise exception 'Spieler ist nicht in deinem Kader';
  end if;
  delete from fantasy_rosters
    where league_id = p_league_id and player_id = p_player_id
      and manager_id = auth.uid();
end$$;

-- Direkte FA-Aufnahme (freie Aufnahme ohne Wartezeit). Optionaler Drop,
-- um Platz zu schaffen. Kadergröße wird nie überschritten.
create function public.fantasy_add_free_agent(
  p_league_id uuid, p_add_player_id text, p_drop_player_id text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_roster jsonb; v_locked boolean; v_count int;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  select season, roster into v_season, v_roster
    from fantasy_leagues where id = p_league_id for update;

  if not exists (select 1 from players where id = p_add_player_id) then
    raise exception 'Spieler unbekannt';
  end if;
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_add_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;

  select public.fantasy_is_locked(birth_date, is_foreign_newcomer, v_season, now())
    into v_locked from players where id = p_add_player_id;
  if v_locked then
    raise exception 'Spieler ist gesperrt (U20/Neuzugang, für den U20-Draft reserviert)';
  end if;

  if p_drop_player_id is not null then
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and player_id = p_drop_player_id
                     and manager_id = auth.uid()) then
      raise exception 'Abzugebender Spieler ist nicht in deinem Kader';
    end if;
    delete from fantasy_rosters
      where league_id = p_league_id and player_id = p_drop_player_id
        and manager_id = auth.uid();
  end if;

  select count(*) into v_count from fantasy_rosters
    where league_id = p_league_id and manager_id = auth.uid();
  if v_count >= public.fantasy_squad_size(v_roster) then
    raise exception 'Kader voll – du musst einen Spieler abgeben';
  end if;

  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
  values (p_league_id, auth.uid(), p_add_player_id, 'fa');
end$$;
