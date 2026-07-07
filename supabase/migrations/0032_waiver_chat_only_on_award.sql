-- Waiver im Liga-Chat nur noch beim Zuschlag melden.
--
-- Bisher (0029) postete der Server schon beim Auf-den-Wire-Legen eine
-- Chat-Meldung ("… auf den Waiver gelegt") – sowohl beim reinen Drop als auch
-- als Zusatz der Free-Agency-Verpflichtung. Gewünscht ist, dass Waiver-Aktivität
-- im Chat erst sichtbar wird, wenn ein Antrag durchgeht (Zuschlag, weiterhin
-- "📥 … über den Waiver geholt" in fantasy_process_due_waivers).
--
-- Daher: die beiden Funktionen ohne die "auf den Waiver gelegt"-Meldungen
-- neu anlegen. Fachlogik (Drop, Wire, Kaderprüfung) bleibt identisch zu 0029.

-- ---------------------------------------------------------------------
-- Drop: keine Chat-Meldung mehr.
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
end$$;

-- ---------------------------------------------------------------------
-- Free-Agency-Aufnahme: Verpflichtung melden, aber ohne Waiver-Zusatz.
-- ---------------------------------------------------------------------
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

  perform public.fantasy_post_system_message(p_league_id,
    '✅ ' || public._fantasy_username(auth.uid()) || ' hat '
      || public._fantasy_playername(p_add_player_id) || ' verpflichtet.');
end$$;
