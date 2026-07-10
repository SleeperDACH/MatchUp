-- Beitritt NACH Draft-Start: Eingeladene können der Liga weiterhin beitreten,
-- allerdings als „pending" (ohne Team). Der Admin weist sie später einem
-- FREIEN (verwaisten) Team zu. Es entstehen dadurch KEINE neuen Teams — die
-- Team-Anzahl der Liga bleibt nach dem Draft fix.

alter table public.fantasy_league_members
  add column if not exists pending boolean not null default false;

-- join: vor dem Draft normal (mit 18er-Limit), danach als pending.
create or replace function public.join_fantasy_league(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_league_id uuid;
  v_status    text;
  v_max       int;
  v_effective int;
  v_count     int;
begin
  select id, draft_status, max_teams into v_league_id, v_status, v_max
  from fantasy_leagues where invite_code = p_invite_code;
  if v_league_id is null then
    raise exception 'Ungültiger Einladungscode';
  end if;
  -- Bereits Mitglied (aktiv oder pending)? Dann idempotent zurückgeben.
  if exists (select 1 from fantasy_league_members
             where league_id = v_league_id and user_id = auth.uid()) then
    return v_league_id;
  end if;

  if v_status = 'setup' then
    -- Vor dem Draft: reguläres Team, effektives Limit min(max_teams, 18).
    v_effective := least(coalesce(v_max, 18), 18);
    select count(*) into v_count
      from fantasy_league_members where league_id = v_league_id;
    if v_count >= v_effective then
      raise exception 'Die Liga ist voll (% Teilnehmer)', v_effective;
    end if;
    insert into fantasy_league_members (league_id, user_id)
    values (v_league_id, auth.uid())
    on conflict do nothing;
  else
    -- Draft läuft/beendet: als pending beitreten (kein Team). Der Admin weist
    -- später ein verwaistes Team zu, sofern ein Platz frei ist.
    insert into fantasy_league_members (league_id, user_id, pending)
    values (v_league_id, auth.uid(), true)
    on conflict do nothing;
  end if;
  return v_league_id;
end;
$$;

-- assign: darf ein pending-Mitglied als neuen Team-Manager akzeptieren und
-- hebt dessen pending-Status auf. Ein NICHT-verwaistes, NICHT-pending Mitglied
-- bleibt weiterhin gesperrt (schon aktives Team).
create or replace function public.fantasy_assign_team(
  p_league_id uuid, p_vacant_user uuid, p_new_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_pos int; v_prio int;
begin
  if not public.fantasy_is_admin(p_league_id) then
    raise exception 'Nur der Admin kann Teams zuweisen';
  end if;
  if not exists (select 1 from profiles where id = p_new_user) then
    raise exception 'Nutzer unbekannt';
  end if;
  select draft_position, waiver_priority into v_pos, v_prio
    from fantasy_league_members
    where league_id = p_league_id and user_id = p_vacant_user and vacant;
  if not found then raise exception 'Kein verwaistes Team gefunden'; end if;

  -- Gleicher Nutzer kehrt zurück: nur reaktivieren.
  if p_new_user = p_vacant_user then
    update fantasy_league_members set vacant = false, pending = false
      where league_id = p_league_id and user_id = p_vacant_user;
    return;
  end if;

  if exists (select 1 from fantasy_league_members
             where league_id = p_league_id and user_id = p_new_user
               and not vacant and not pending) then
    raise exception 'Nutzer ist bereits aktives Mitglied';
  end if;

  -- Kader & Nebendaten auf den neuen Nutzer umschreiben.
  update fantasy_rosters set manager_id = p_new_user
    where league_id = p_league_id and manager_id = p_vacant_user;
  update fantasy_lineups set manager_id = p_new_user
    where league_id = p_league_id and manager_id = p_vacant_user;
  update draft_picks set manager_id = p_new_user
    where league_id = p_league_id and manager_id = p_vacant_user;
  update fantasy_waiver_claims set manager_id = p_new_user
    where league_id = p_league_id and manager_id = p_vacant_user;

  -- Mitglieds-Slot auf den neuen Nutzer übertragen (pending wird aufgehoben).
  delete from fantasy_league_members
    where league_id = p_league_id and user_id = p_vacant_user;
  insert into fantasy_league_members (league_id, user_id, draft_position, waiver_priority, vacant, pending)
    values (p_league_id, p_new_user, v_pos, v_prio, false, false)
    on conflict (league_id, user_id)
      do update set draft_position = excluded.draft_position,
                    waiver_priority = excluded.waiver_priority,
                    vacant = false, pending = false;
end$$;
