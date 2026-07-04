-- Erweiterte Liga-Einstellungen: Teilnehmer-Limit und Slow-Draft-Pausenfenster.
-- Die Anzahl Draft-Runden steckt weiter in der roster-JSONB (squadSize =
-- Startelf + Bank) und wird clientseitig über die Bank angepasst.
--
-- * max_teams: maximale Teilnehmerzahl (null = unbegrenzt), beim Beitritt geprüft.
-- * draft_pause_start / draft_pause_end: Minute des Tages (0–1439, Europe/Berlin)
--   für ein tägliches Pausenfenster im Slow-Draft — darin picken abgelaufene
--   Picks nicht automatisch (z. B. nachts). null = keine Pause.

alter table public.fantasy_leagues
  add column if not exists max_teams int,
  add column if not exists draft_pause_start smallint,
  add column if not exists draft_pause_end smallint;

-- ---------------------------------------------------------------------
-- Beitritt: Teilnehmer-Limit prüfen.
-- ---------------------------------------------------------------------
create or replace function public.join_fantasy_league(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_league_id uuid;
  v_status    text;
  v_max       int;
  v_count     int;
begin
  select id, draft_status, max_teams into v_league_id, v_status, v_max
  from fantasy_leagues where invite_code = p_invite_code;
  if v_league_id is null then
    raise exception 'Ungültiger Einladungscode';
  end if;
  if v_status <> 'setup' then
    raise exception 'Der Draft dieser Liga hat bereits begonnen';
  end if;
  -- Bereits Mitglied? Dann einfach zurückgeben (idempotent, kein Limit-Fehler).
  if exists (select 1 from fantasy_league_members
             where league_id = v_league_id and user_id = auth.uid()) then
    return v_league_id;
  end if;
  if v_max is not null then
    select count(*) into v_count
      from fantasy_league_members where league_id = v_league_id;
    if v_count >= v_max then
      raise exception 'Die Liga ist voll (% Teilnehmer)', v_max;
    end if;
  end if;
  insert into fantasy_league_members (league_id, user_id)
  values (v_league_id, auth.uid())
  on conflict do nothing;
  return v_league_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Autopick: im Slow-Draft-Pausenfenster nicht automatisch picken.
-- (ansonsten unverändert zu 0005)
-- ---------------------------------------------------------------------
create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int;
  v_pause_start smallint; v_pause_end smallint; v_minute int;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season,
         draft_pause_start, draft_pause_end
    into v_status, v_deadline, v_mode, v_phase, v_season,
         v_pause_start, v_pause_end
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;
  if v_deadline is null or now() <= v_deadline then return false; end if;

  -- Pausenfenster (Europe/Berlin): innerhalb nicht auto-picken.
  if v_pause_start is not null and v_pause_end is not null then
    v_minute := extract(hour from now() at time zone 'Europe/Berlin') * 60
              + extract(minute from now() at time zone 'Europe/Berlin');
    if (v_pause_start <= v_pause_end
          and v_minute >= v_pause_start and v_minute < v_pause_end)
       or (v_pause_start > v_pause_end
          and (v_minute >= v_pause_start or v_minute < v_pause_end)) then
      return false;
    end if;
  end if;

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
