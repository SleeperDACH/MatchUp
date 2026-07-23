-- Zwei Draft-Fixes:
--  1) Auto-Pick wählt den bestplatzierten freien Spieler (nach projizierten
--     Vorsaison-Punkten mit dem Liga-Scoring), statt alphabetisch nach Name.
--  2) Der U20-Draft startet „normal": das auto_pick-Flag aus dem vorherigen
--     Aufbau-Draft wird zurückgesetzt, damit die Manager nicht sofort weiter
--     automatisch picken.

-- Auto-Pick mit Ranking-Reihenfolge im Rückfall (Queue bleibt nach q.rank).
create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int; v_away boolean; v_expired boolean;
  v_scoring jsonb; v_last_season int;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season, scoring
    into v_status, v_deadline, v_mode, v_phase, v_season, v_scoring
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;

  -- Letzte abgeschlossene Saison für die Ranking-Punkte — kalenderbasiert wie
  -- der Client (Saison = Startjahr; ab Juli das laufende Jahr), minus 1.
  v_last_season := (case when extract(month from now())::int >= 7
                         then extract(year from now())::int
                         else extract(year from now())::int - 1 end) - 1;

  if auth.uid() is not null and not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  v_manager := public.fantasy_current_manager(p_league_id);
  select coalesce(auto_pick, false) into v_away
    from fantasy_league_members
    where league_id = p_league_id and user_id = v_manager;

  v_expired := v_deadline is not null and now() > v_deadline;
  if not v_expired and not coalesce(v_away, false) then return false; end if;

  -- Queue zuerst (nach Wunschreihenfolge des Managers).
  select q.player_id into v_player
    from fantasy_draft_queue q join players p on p.id = q.player_id
    where q.league_id = p_league_id and q.manager_id = v_manager
      and q.player_id not in
          (select player_id from fantasy_rosters where league_id = p_league_id)
      and (v_mode <> 'dynasty'
           or v_phase <> 'u20'
           or public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
    order by q.rank limit 1;

  -- Rückfall: bester freier, phasen-gültiger Spieler nach projizierten
  -- Vorsaison-Punkten (gleiche Formel wie die Client-Draftreihung).
  if v_player is null then
    select p.id into v_player
      from players p
      left join player_season_totals t
        on t.player_id = p.id and t.season = v_last_season
      where p.id not in
            (select player_id from fantasy_rosters where league_id = p_league_id)
        and (v_mode <> 'dynasty'
             or v_phase <> 'u20'
             or public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
      order by (
          coalesce(t.appearances, 0)
            * coalesce((v_scoring->>'appearance')::int, 2)
        + coalesce(t.goals, 0) * (case p.position
            when 'gk'  then coalesce((v_scoring->>'goalGk')::int, 6)
            when 'def' then coalesce((v_scoring->>'goalDef')::int, 6)
            when 'mid' then coalesce((v_scoring->>'goalMid')::int, 5)
            else            coalesce((v_scoring->>'goalFwd')::int, 4) end)
        + coalesce(t.assists, 0) * coalesce((v_scoring->>'assist')::int, 3)
        + (case when p.position in ('gk', 'def')
                then coalesce(t.clean_sheets, 0)
                     * coalesce((v_scoring->>'cleanSheetGkDef')::int, 4)
                else 0 end)
        + coalesce(t.yellow, 0) * coalesce((v_scoring->>'yellowCard')::int, -1)
        + coalesce(t.red, 0) * coalesce((v_scoring->>'redCard')::int, -3)
      ) desc, p.name asc
      limit 1;
  end if;

  if v_player is null then
    update fantasy_leagues
      set draft_status = 'done', current_pick_deadline = null
      where id = p_league_id;
    return false;
  end if;

  if v_expired then
    update fantasy_league_members set auto_pick = true
      where league_id = p_league_id and user_id = v_manager;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, v_player, true);
  return true;
end$$;

-- U20-Draft startet ohne übernommenes Auto-Pick: alle Manager wieder aktiv.
create or replace function public.start_u20_draft(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_mode text; v_secs int; v_pending boolean;
begin
  select created_by, mode, draft_pick_seconds, u20_draft_pending
    into v_created_by, v_mode, v_secs, v_pending
    from fantasy_leagues where id = p_league_id for update;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den U20-Draft starten';
  end if;
  if v_mode <> 'dynasty' then raise exception 'U20-Draft nur im Dynasty-Modus'; end if;
  if not v_pending then
    raise exception 'Der U20-Draft steht gerade nicht an (erst nach dem Saison-Rollover)';
  end if;

  -- Auto-Pick aus dem Aufbau-Draft zurücksetzen — der U20-Draft startet normal.
  update fantasy_league_members set auto_pick = false
    where league_id = p_league_id;

  update fantasy_leagues
    set draft_phase = 'u20', draft_status = 'drafting',
        picks_made = 0, u20_draft_pending = false,
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;
