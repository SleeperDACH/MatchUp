-- Automatische System-Nachrichten im Liga-Chat bei Kaderänderungen.
--
-- Droppt/verpflichtet jemand einen Spieler (Free Agency, Waiver) oder ändert
-- der Admin einen fremden Kader, postet der Server eine neutrale Mitteilung im
-- Fantasy-Liga-Chat. System-Nachrichten haben keinen Absender (user_id null)
-- und ein Flag [is_system]; der Client stellt sie als dezente Zeile dar.

alter table public.fantasy_league_messages
  add column if not exists is_system boolean not null default false;
alter table public.fantasy_league_messages
  alter column user_id drop not null;

-- Neutrale Chat-Mitteilung posten (Server-seitig, umgeht die Insert-RLS).
create function public.fantasy_post_system_message(p_league_id uuid, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into fantasy_league_messages (league_id, user_id, body, is_system)
  values (p_league_id, null, left(p_body, 1000), true);
$$;

-- Hilfsfunktionen für Namen (immutable/stable, für die Meldungstexte).
create function public._fantasy_username(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select username from profiles where id = p_user), 'Jemand');
$$;

create function public._fantasy_playername(p_player text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select name from players where id = p_player), p_player);
$$;

-- ---------------------------------------------------------------------
-- Drop (mit Chat-Meldung)
-- ---------------------------------------------------------------------
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
  perform public.fantasy_post_system_message(p_league_id,
    '🔻 ' || public._fantasy_username(auth.uid()) || ' hat '
      || public._fantasy_playername(p_player_id) || ' auf den Waiver gelegt.');
end$$;

-- ---------------------------------------------------------------------
-- Free-Agency-Aufnahme (mit Chat-Meldung)
-- ---------------------------------------------------------------------
create or replace function public.fantasy_add_free_agent(
  p_league_id uuid, p_add_player_id text, p_drop_player_id text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_roster jsonb; v_locked boolean; v_count int; v_msg text;
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

  v_msg := '✅ ' || public._fantasy_username(auth.uid()) || ' hat '
    || public._fantasy_playername(p_add_player_id) || ' verpflichtet';
  if p_drop_player_id is not null then
    v_msg := v_msg || ' und ' || public._fantasy_playername(p_drop_player_id)
      || ' auf den Waiver gelegt';
  end if;
  perform public.fantasy_post_system_message(p_league_id, v_msg || '.');
end$$;

-- ---------------------------------------------------------------------
-- Admin-Kaderbearbeitung (mit Chat-Meldung)
-- ---------------------------------------------------------------------
create or replace function public.fantasy_admin_drop(
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
  perform public.fantasy_post_system_message(p_league_id,
    '🛠️ Admin ' || public._fantasy_username(auth.uid()) || ' hat '
      || public._fantasy_playername(p_player_id) || ' aus dem Kader von '
      || public._fantasy_username(p_target) || ' entfernt (Waiver).');
end$$;

create or replace function public.fantasy_admin_add(
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
  delete from fantasy_waiver_players
    where league_id = p_league_id and player_id = p_player_id;
  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
    values (p_league_id, p_target, p_player_id, 'fa');
  perform public.fantasy_post_system_message(p_league_id,
    '🛠️ Admin ' || public._fantasy_username(auth.uid()) || ' hat '
      || public._fantasy_playername(p_player_id) || ' zum Kader von '
      || public._fantasy_username(p_target) || ' hinzugefügt.');
end$$;

-- ---------------------------------------------------------------------
-- Waiver-Zuschlag (mit Chat-Meldung) — 0028-Version + Meldung.
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
      perform public.fantasy_post_system_message(w.league_id,
        '📥 ' || public._fantasy_username(v_claim.manager_id) || ' hat '
          || public._fantasy_playername(w.player_id) || ' über den Waiver geholt.');
      v_awarded := true;
      exit;
    end loop;

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
