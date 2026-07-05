-- Verwaiste Teams, Admin-Rechte (Commissioner) und 24h-Waiver.
--
-- * Verlässt/kickt man einen Teilnehmer, bleibt sein Team (Kader) als
--   „verwaist" bestehen; der Admin kann es einem neuen Nutzer zuweisen, der
--   den bestehenden Kader übernimmt.
-- * Der Admin (Liga-Ersteller) darf fremde Kader bearbeiten (Spieler
--   droppen / freie Spieler zuweisen) und Teilnehmer kicken.
-- * Jeder gedroppte Spieler ist erst 24 Stunden auf dem Waiver-Wire
--   (claim-only, rollende Priorität), danach frei. Die Verarbeitung läuft
--   pro Spieler zum Ablauf seiner 24h (Cron alle 10 Min).

-- ---------------------------------------------------------------------
-- Mitgliedschaft: verwaiste Teams
-- ---------------------------------------------------------------------
alter table public.fantasy_league_members
  add column if not exists vacant boolean not null default false;

-- Verwaiste Slots zählen nicht als aktive Mitgliedschaft (kein Zugriff mehr).
create or replace function public.is_fantasy_member(p_league_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from fantasy_league_members
    where league_id = p_league_id and user_id = auth.uid() and not vacant
  );
$$;

-- Admin = Liga-Ersteller.
create function public.fantasy_is_admin(p_league_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from fantasy_leagues where id = p_league_id and created_by = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------
-- Waiver-Helfer: Spieler für 24h auf den Wire setzen
-- ---------------------------------------------------------------------
create function public.fantasy_put_on_wire(p_league_id uuid, p_player_id text)
returns void language sql security definer set search_path = public as $$
  insert into fantasy_waiver_players (league_id, player_id, clears_at)
  values (p_league_id, p_player_id, now() + interval '24 hours')
  on conflict (league_id, player_id) do update set clears_at = excluded.clears_at;
$$;

-- Drop kommt jetzt für 24h auf den Wire.
create or replace function public.fantasy_drop_player(
  p_league_id uuid, p_player_id text)
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
  perform public.fantasy_put_on_wire(p_league_id, p_player_id);
end$$;

-- FA-Aufnahme: optionaler Drop kommt ebenfalls für 24h auf den Wire.
create or replace function public.fantasy_add_free_agent(
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
  if exists (select 1 from fantasy_waiver_players
             where league_id = p_league_id and player_id = p_add_player_id
               and clears_at > now()) then
    raise exception 'Spieler ist auf dem Waiver – bitte per Antrag holen';
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
    perform public.fantasy_put_on_wire(p_league_id, p_drop_player_id);
  end if;

  select count(*) into v_count from fantasy_rosters
    where league_id = p_league_id and manager_id = auth.uid();
  if v_count >= public.fantasy_squad_size(v_roster) then
    raise exception 'Kader voll – du musst einen Spieler abgeben';
  end if;

  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
  values (p_league_id, auth.uid(), p_add_player_id, 'fa');
end$$;

-- ---------------------------------------------------------------------
-- Verlassen: Team bleibt als verwaister Slot bestehen (Kader unangetastet).
-- ---------------------------------------------------------------------
create or replace function public.leave_fantasy_league(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Nicht angemeldet'; end if;
  select created_by, draft_status into v_created_by, v_status
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if v_created_by = v_uid then
    raise exception 'Der Ersteller kann die Liga nicht verlassen — nur löschen';
  end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = v_uid and not vacant) then
    raise exception 'Du bist kein Mitglied dieser Liga';
  end if;
  if v_status = 'drafting' then
    raise exception 'Während des laufenden Drafts kann die Liga nicht verlassen werden';
  end if;

  perform public._fantasy_vacate(p_league_id, v_uid);
end$$;

-- Gemeinsame Vacate-Logik (Verlassen wie Kick): Slot verwaisen, Kader
-- behalten, aber laufende Nebendaten des Nutzers räumen.
create function public._fantasy_vacate(p_league_id uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from fantasy_draft_queue where league_id = p_league_id and manager_id = p_user;
  update fantasy_waiver_claims set status = 'cancelled', reason = 'Team verwaist',
         processed_at = now()
    where league_id = p_league_id and manager_id = p_user and status = 'pending';
  update fantasy_league_members set vacant = true, auto_pick = false
    where league_id = p_league_id and user_id = p_user;
end$$;

-- Admin kickt einen Teilnehmer (Slot wird verwaist, Kader bleibt).
create function public.fantasy_kick_member(p_league_id uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_created_by uuid; v_status text;
begin
  select created_by, draft_status into v_created_by, v_status
    from fantasy_leagues where id = p_league_id for update;
  if auth.uid() <> v_created_by then raise exception 'Nur der Admin kann kicken'; end if;
  if p_user = v_created_by then raise exception 'Der Admin kann sich nicht selbst kicken'; end if;
  if v_status = 'drafting' then
    raise exception 'Während des laufenden Drafts kann niemand gekickt werden';
  end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = p_user and not vacant) then
    raise exception 'Kein aktives Mitglied';
  end if;
  perform public._fantasy_vacate(p_league_id, p_user);
end$$;

-- Admin weist ein verwaistes Team einem neuen Nutzer zu (übernimmt den Kader).
create function public.fantasy_assign_team(
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
    update fantasy_league_members set vacant = false
      where league_id = p_league_id and user_id = p_vacant_user;
    return;
  end if;

  if exists (select 1 from fantasy_league_members
             where league_id = p_league_id and user_id = p_new_user and not vacant) then
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

  -- Mitglieds-Slot auf den neuen Nutzer übertragen.
  delete from fantasy_league_members
    where league_id = p_league_id and user_id = p_vacant_user;
  insert into fantasy_league_members (league_id, user_id, draft_position, waiver_priority, vacant)
    values (p_league_id, p_new_user, v_pos, v_prio, false)
    on conflict (league_id, user_id)
      do update set draft_position = excluded.draft_position,
                    waiver_priority = excluded.waiver_priority, vacant = false;
end$$;

-- ---------------------------------------------------------------------
-- Admin-Kaderbearbeitung (Commissioner)
-- ---------------------------------------------------------------------
create function public.fantasy_admin_drop(
  p_league_id uuid, p_target uuid, p_player_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.fantasy_is_admin(p_league_id) then
    raise exception 'Nur der Admin darf Kader bearbeiten';
  end if;
  if not exists (select 1 from fantasy_rosters
                 where league_id = p_league_id and player_id = p_player_id
                   and manager_id = p_target) then
    raise exception 'Spieler nicht im Kader dieses Teams';
  end if;
  delete from fantasy_rosters
    where league_id = p_league_id and player_id = p_player_id and manager_id = p_target;
  perform public.fantasy_put_on_wire(p_league_id, p_player_id);
end$$;

create function public.fantasy_admin_add(
  p_league_id uuid, p_target uuid, p_player_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.fantasy_is_admin(p_league_id) then
    raise exception 'Nur der Admin darf Kader bearbeiten';
  end if;
  if not exists (select 1 from players where id = p_player_id) then
    raise exception 'Spieler unbekannt';
  end if;
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = p_target and not vacant) then
    raise exception 'Zielteam ist kein aktives Mitglied';
  end if;
  -- Commissioner: Sperren/Limits werden bewusst übergangen; Wire-Eintrag frei.
  delete from fantasy_waiver_players
    where league_id = p_league_id and player_id = p_player_id;
  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
    values (p_league_id, p_target, p_player_id, 'fa');
end$$;

-- ---------------------------------------------------------------------
-- Waiver-Verarbeitung: pro Spieler zum Ablauf seiner 24h.
-- ---------------------------------------------------------------------
create or replace function public.fantasy_process_due_waivers()
returns void language plpgsql security definer set search_path = public as $$
declare
  w record; v_claim record; v_squad int; v_have int; v_frees int; v_awarded boolean;
begin
  for w in
    select league_id, player_id from fantasy_waiver_players
    where clears_at <= now() order by clears_at
  loop
    -- Spieler evtl. inzwischen schon in einem Kader → nur vom Wire nehmen.
    if exists (select 1 from fantasy_rosters
               where league_id = w.league_id and player_id = w.player_id) then
      delete from fantasy_waiver_players
        where league_id = w.league_id and player_id = w.player_id;
      continue;
    end if;

    select public.fantasy_squad_size(roster) into v_squad
      from fantasy_leagues where id = w.league_id;
    v_awarded := false;

    for v_claim in
      select c.*
      from fantasy_waiver_claims c
      join fantasy_league_members m
        on m.league_id = c.league_id and m.user_id = c.manager_id and not m.vacant
      where c.league_id = w.league_id and c.add_player_id = w.player_id
        and c.status = 'pending'
      order by m.waiver_priority asc nulls last, c.rank asc, c.created_at asc
    loop
      v_frees := 0;
      if v_claim.drop_player_id is not null and exists (
           select 1 from fantasy_rosters
           where league_id = w.league_id and player_id = v_claim.drop_player_id
             and manager_id = v_claim.manager_id) then
        v_frees := 1;
      end if;
      select count(*) into v_have from fantasy_rosters
        where league_id = w.league_id and manager_id = v_claim.manager_id;
      if v_have - v_frees >= v_squad then
        update fantasy_waiver_claims set status = 'invalid',
               reason = 'Kader voll – Drop nötig', processed_at = now()
          where id = v_claim.id;
        continue;
      end if;

      if v_frees = 1 then
        delete from fantasy_rosters
          where league_id = w.league_id and player_id = v_claim.drop_player_id
            and manager_id = v_claim.manager_id;
        perform public.fantasy_put_on_wire(w.league_id, v_claim.drop_player_id);
      end if;
      insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
        values (w.league_id, v_claim.manager_id, w.player_id, 'waiver');
      update fantasy_waiver_claims set status = 'won', processed_at = now()
        where id = v_claim.id;
      update fantasy_league_members
        set waiver_priority = (select coalesce(max(waiver_priority), 0) + 1
                               from fantasy_league_members
                               where league_id = w.league_id and not vacant)
        where league_id = w.league_id and user_id = v_claim.manager_id;
      v_awarded := true;
      exit;
    end loop;

    -- Spieler vom Wire nehmen (vergeben oder Frist abgelaufen → frei).
    delete from fantasy_waiver_players
      where league_id = w.league_id and player_id = w.player_id;
    update fantasy_waiver_claims
      set status = 'lost',
          reason = case when v_awarded then 'Spieler anderweitig vergeben'
                        else 'Frist abgelaufen – Spieler frei' end,
          processed_at = now()
      where league_id = w.league_id and add_player_id = w.player_id
        and status = 'pending';
  end loop;
end$$;
