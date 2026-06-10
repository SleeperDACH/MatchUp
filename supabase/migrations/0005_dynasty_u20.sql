-- Dynasty-Modus (Phase 3): U20-Sperre und U20-Draft.
--
-- Mechanik: Im Dynasty-Haupt-Draft ("startup") sind nur etablierte
-- Spieler wählbar. U20-Spieler (Alter < 20 zum 1. Spieltag) und
-- Auslands-Neuzugänge sind gesperrt und werden danach im separaten
-- U20-Draft ("u20") gewählt — Vorbereitung auf die neue Saison.
-- Beide Phasen nutzen dieselbe Snake-Engine; die Phase steht auf der
-- Liga und an jedem Pick.

alter table public.fantasy_leagues
  add column draft_phase text not null default 'startup'
    check (draft_phase in ('startup', 'u20')),
  add column u20_rounds int not null default 3;

alter table public.draft_picks
  add column phase text not null default 'startup';
alter table public.draft_picks drop constraint draft_picks_pkey;
alter table public.draft_picks add primary key (league_id, phase, pick_number);

-- "Rookie" = im U20-Draft wählbar: U20 zum 1. Spieltag oder Auslands-Neuzugang.
create function public.fantasy_is_rookie(
  p_birth_date date, p_is_foreign boolean, p_season int)
returns boolean language sql immutable as $$
  select p_is_foreign
      or extract(year from age(make_date(p_season, 8, 1), p_birth_date)) < 20;
$$;

-- Vorrücken jetzt phasenabhängig (Gesamtzahl Picks: Haupt = Kadergröße,
-- U20 = u20_rounds), schreibt die Phase mit.
create or replace function public.fantasy_advance(
  p_league_id uuid, p_manager uuid, p_player text, p_is_auto boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_p int; v_n int; v_squad int; v_total int; v_secs int;
  v_phase text; v_u20 int;
begin
  select picks_made, draft_pick_seconds, public.fantasy_squad_size(roster),
         draft_phase, u20_rounds
    into v_p, v_secs, v_squad, v_phase, v_u20
    from fantasy_leagues where id = p_league_id;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  v_total := v_n * (case when v_phase = 'u20' then v_u20 else v_squad end);

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

-- Manueller Pick mit Phasen-Pool-Prüfung (nur Dynasty).
create or replace function public.fantasy_make_pick(p_league_id uuid, p_player_id text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_mode text; v_phase text; v_season int;
  v_manager uuid; v_exists int; v_rookie boolean;
begin
  select draft_status, mode, draft_phase, season
    into v_status, v_mode, v_phase, v_season
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then raise exception 'Der Draft läuft nicht'; end if;

  v_manager := public.fantasy_current_manager(p_league_id);
  if auth.uid() <> v_manager then raise exception 'Du bist nicht am Zug'; end if;

  select count(*) into v_exists from players where id = p_player_id;
  if v_exists = 0 then raise exception 'Spieler unbekannt'; end if;
  if exists (select 1 from draft_picks
             where league_id = p_league_id and player_id = p_player_id) then
    raise exception 'Spieler ist bereits gedraftet';
  end if;

  if v_mode = 'dynasty' then
    select public.fantasy_is_rookie(birth_date, is_foreign_newcomer, v_season)
      into v_rookie from players where id = p_player_id;
    if v_phase = 'startup' and v_rookie then
      raise exception 'Im Haupt-Draft nur etablierte Spieler (U20/Neuzugänge folgen im U20-Draft)';
    end if;
    if v_phase = 'u20' and not v_rookie then
      raise exception 'Im U20-Draft nur U20-Spieler und Auslands-Neuzugänge wählbar';
    end if;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, p_player_id, false);
end$$;

-- Auto-Pick respektiert den Phasen-Pool.
create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season
    into v_status, v_deadline, v_mode, v_phase, v_season
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;
  if v_deadline is null or now() <= v_deadline then return false; end if;

  if auth.uid() is not null and not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  v_manager := public.fantasy_current_manager(p_league_id);

  select p.id into v_player from players p
    where p.id not in (select player_id from draft_picks where league_id = p_league_id)
      and (v_mode <> 'dynasty'
           or (v_phase = 'u20')
              = public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
    order by p.name limit 1;

  if v_player is null then
    update fantasy_leagues
      set draft_status = 'done', current_pick_deadline = null
      where id = p_league_id;
    return false;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, v_player, true);
  return true;
end$$;

-- Haupt-Draft startet immer in Phase 'startup'.
create or replace function public.start_fantasy_draft(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_n int; v_secs int;
begin
  select created_by, draft_status, draft_pick_seconds
    into v_created_by, v_status, v_secs
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den Draft starten';
  end if;
  if v_status <> 'setup' then raise exception 'Der Draft wurde bereits gestartet'; end if;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  if v_n < 1 then raise exception 'Mindestens ein Manager nötig'; end if;

  with shuffled as (
    select user_id, row_number() over (order by random()) as pos
    from fantasy_league_members where league_id = p_league_id
  )
  update fantasy_league_members m
    set draft_position = s.pos
    from shuffled s
    where m.league_id = p_league_id and m.user_id = s.user_id;

  update fantasy_leagues
    set draft_status = 'drafting', draft_phase = 'startup',
        picks_made = 0, draft_started_at = now(),
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;

-- U20-Draft starten (Dynasty, nach abgeschlossenem Haupt-Draft).
create function public.start_u20_draft(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_phase text; v_mode text; v_secs int;
begin
  select created_by, draft_status, draft_phase, mode, draft_pick_seconds
    into v_created_by, v_status, v_phase, v_mode, v_secs
    from fantasy_leagues where id = p_league_id for update;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den U20-Draft starten';
  end if;
  if v_mode <> 'dynasty' then raise exception 'U20-Draft nur im Dynasty-Modus'; end if;
  if not (v_status = 'done' and v_phase = 'startup') then
    raise exception 'Der Haupt-Draft muss erst abgeschlossen sein';
  end if;

  update fantasy_leagues
    set draft_phase = 'u20', draft_status = 'drafting',
        picks_made = 0,
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;
