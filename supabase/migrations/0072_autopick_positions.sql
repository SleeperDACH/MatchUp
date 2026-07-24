-- Auto-Pick füllt zuerst die Startelf, dann die Bank.
--
-- Regeln (aufbauend auf 0068_autopick_ranking):
--  * Die Wunschliste (fantasy_draft_queue) gewinnt weiterhin immer: ein
--    gewünschter, freier Spieler wird sofort gezogen, egal welche Position.
--  * Im Ranking-Rückfall respektiert der Auto-Pick die Kaderstruktur:
--    - Startelf-Phase (irgendeine der Gruppen gk/def/mid/fwd noch nicht voll):
--      Es wird der bestplatzierte freie Spieler einer NOCH OFFENEN Gruppe
--      gezogen. Spieler bereits voller Gruppen werden übersprungen.
--    - Bank-Phase (Startelf komplett): kein Torwart auf die Bank; die
--      Reserveplätze werden gleichmäßig über Abwehr/Mittelfeld/Angriff
--      verteilt (immer die Gruppe mit den wenigsten Bankspielern zuerst),
--      Ranking als Tiebreak.
--  * Positionen sind nur SORTIER-Priorität, kein harter Filter: ist der Pool
--    einer bevorzugten Gruppe leer, wird notfalls trotzdem ein anderer Spieler
--    gezogen. So beendet der Draft nie versehentlich vorzeitig (draft_status =
--    'done' nur, wenn wirklich kein freier Spieler mehr existiert).

create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int; v_away boolean; v_expired boolean;
  v_scoring jsonb; v_last_season int; v_roster jsonb;
  v_tgt_gk int; v_tgt_def int; v_tgt_mid int; v_tgt_fwd int;
  v_cnt_gk int; v_cnt_def int; v_cnt_mid int; v_cnt_fwd int;
  v_starter_phase boolean;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season,
         scoring, roster
    into v_status, v_deadline, v_mode, v_phase, v_season, v_scoring, v_roster
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

  -- Kader-Sollwerte (gleiche Defaults wie fantasy_squad_size).
  v_tgt_gk  := coalesce((v_roster->>'gk')::int, 1);
  v_tgt_def := coalesce((v_roster->>'def')::int, 4);
  v_tgt_mid := coalesce((v_roster->>'mid')::int, 4);
  v_tgt_fwd := coalesce((v_roster->>'fwd')::int, 2);

  -- Aktuelle Kaderzusammensetzung des Managers.
  select count(*) filter (where p.position = 'gk'),
         count(*) filter (where p.position = 'def'),
         count(*) filter (where p.position = 'mid'),
         count(*) filter (where p.position = 'fwd')
    into v_cnt_gk, v_cnt_def, v_cnt_mid, v_cnt_fwd
    from fantasy_rosters r join players p on p.id = r.player_id
    where r.league_id = p_league_id and r.manager_id = v_manager;

  -- Startelf-Phase, solange irgendeine Positionsgruppe noch nicht voll ist.
  v_starter_phase := v_cnt_gk  < v_tgt_gk  or v_cnt_def < v_tgt_def
                  or v_cnt_mid < v_tgt_mid or v_cnt_fwd < v_tgt_fwd;

  -- Queue zuerst (nach Wunschreihenfolge des Managers) — gewinnt immer,
  -- unabhängig von der Position.
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
  -- Vorsaison-Punkten (gleiche Formel wie die Client-Draftreihung), aber
  -- positions-priorisiert (Startelf vor Bank, siehe Kopfkommentar).
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
      order by
        -- Positions-Priorität (kleiner = zuerst).
        (case when v_starter_phase then
           -- Startelf: noch offene Gruppen zuerst (0), volle Gruppen zuletzt (1).
           case p.position
             when 'gk'  then (case when v_cnt_gk  < v_tgt_gk  then 0 else 1 end)
             when 'def' then (case when v_cnt_def < v_tgt_def then 0 else 1 end)
             when 'mid' then (case when v_cnt_mid < v_tgt_mid then 0 else 1 end)
             else            (case when v_cnt_fwd < v_tgt_fwd then 0 else 1 end)
           end
         else
           -- Bank: kein Torwart (ganz nach hinten), sonst gleichmäßig über
           -- def/mid/fwd — Gruppe mit den wenigsten Bankspielern zuerst.
           case p.position
             when 'gk'  then 1000000
             when 'def' then (v_cnt_def - v_tgt_def)
             when 'mid' then (v_cnt_mid - v_tgt_mid)
             else            (v_cnt_fwd - v_tgt_fwd)
           end
         end) asc,
        (
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
