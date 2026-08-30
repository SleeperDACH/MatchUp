-- Die Draft-Rangliste kennt die Null hinten fuers Mittelfeld.
--
-- **Die Wertung steht an drei Stellen**, und das ist die dritte:
-- `scoring.config.json`, `fantasy_scoring_rules.dart` und diese SQL-Rangliste,
-- die dieselbe JSONB liest. Tor (15) und Vorlage (10) kommen ueber
-- `fantasy_num` aus der Liga-JSONB und stimmen damit von selbst — die Null
-- hinten steht hier aber **fest**, weil `toJson()` sie nicht serialisiert
-- (siehe die Notiz zu Migration 0079). Wer sie in der Wertung aendert, aendert
-- sie hier mit; genau dafuer diese Migration.
--
-- Ohne sie bewertete der Auto-Pick defensive Mittelfeldspieler weiterhin so,
-- als braechte ihnen eine Null hinten nichts.

CREATE OR REPLACE FUNCTION public.fantasy_autopick_if_expired(p_league_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int; v_away boolean; v_expired boolean;
  v_scoring jsonb; v_last_season int; v_roster jsonb;
  v_tgt_gk int; v_tgt_def int; v_tgt_mid int; v_tgt_fwd int;
  v_cnt_gk int; v_cnt_def int; v_cnt_mid int; v_cnt_fwd int;
  v_starter_phase boolean; v_v2 boolean;
  v_lim_gk numeric; v_lim_def numeric; v_lim_mid numeric; v_lim_fwd numeric;
  v_w_app numeric; v_w_assist numeric; v_w_cs numeric; v_w_cs_mid numeric;
  v_w_yellow numeric; v_w_red numeric;
  v_w_goal_gk numeric; v_w_goal_def numeric;
  v_w_goal_mid numeric; v_w_goal_fwd numeric;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season,
         scoring, roster
    into v_status, v_deadline, v_mode, v_phase, v_season, v_scoring, v_roster
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;

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

  v_tgt_gk  := coalesce((v_roster->>'gk')::int, 1);
  v_tgt_def := coalesce((v_roster->>'def')::int, 4);
  v_tgt_mid := coalesce((v_roster->>'mid')::int, 4);
  v_tgt_fwd := coalesce((v_roster->>'fwd')::int, 2);

  select count(*) filter (where p.position = 'gk'),
         count(*) filter (where p.position = 'def'),
         count(*) filter (where p.position = 'mid'),
         count(*) filter (where p.position = 'fwd')
    into v_cnt_gk, v_cnt_def, v_cnt_mid, v_cnt_fwd
    from fantasy_rosters r join players p on p.id = r.player_id
    where r.league_id = p_league_id and r.manager_id = v_manager;

  v_starter_phase := v_cnt_gk  < v_tgt_gk  or v_cnt_def < v_tgt_def
                  or v_cnt_mid < v_tgt_mid or v_cnt_fwd < v_tgt_fwd;

  -- Kader-Limits (null = unbegrenzt), siehe 0083.
  v_lim_gk  := public.fantasy_num(v_roster, 'maxGk',  null);
  v_lim_def := public.fantasy_num(v_roster, 'maxDef', null);
  v_lim_mid := public.fantasy_num(v_roster, 'maxMid', null);
  v_lim_fwd := public.fantasy_num(v_roster, 'maxFwd', null);

  v_v2 := public.fantasy_num(v_scoring, 'version', 1) >= 2;
  if v_v2 then
    v_w_app       := 10;
    v_w_cs        := 12;
    v_w_cs_mid    := 4;
    v_w_assist    := public.fantasy_num(v_scoring, 'assist', 12);
    v_w_yellow    := public.fantasy_num(v_scoring, 'yellowCard', -4);
    v_w_red       := public.fantasy_num(v_scoring, 'redCard', -10);
    v_w_goal_gk   := public.fantasy_num(v_scoring, 'goal', 16);
    v_w_goal_def  := v_w_goal_gk;
    v_w_goal_mid  := v_w_goal_gk;
    v_w_goal_fwd  := v_w_goal_gk;
  else
    v_w_app       := public.fantasy_num(v_scoring, 'appearance', 2);
    v_w_cs        := public.fantasy_num(v_scoring, 'cleanSheetGkDef', 4);
    v_w_cs_mid    := 0;  -- die alte Wertung kannte das nicht
    v_w_assist    := public.fantasy_num(v_scoring, 'assist', 3);
    v_w_yellow    := public.fantasy_num(v_scoring, 'yellowCard', -1);
    v_w_red       := public.fantasy_num(v_scoring, 'redCard', -3);
    v_w_goal_gk   := public.fantasy_num(v_scoring, 'goalGk', 6);
    v_w_goal_def  := public.fantasy_num(v_scoring, 'goalDef', 6);
    v_w_goal_mid  := public.fantasy_num(v_scoring, 'goalMid', 5);
    v_w_goal_fwd  := public.fantasy_num(v_scoring, 'goalFwd', 4);
  end if;

  -- Queue zuerst — aber auch sie darf kein Limit reißen.
  select q.player_id into v_player
    from fantasy_draft_queue q join players p on p.id = q.player_id
    where q.league_id = p_league_id and q.manager_id = v_manager
      and q.player_id not in
          (select player_id from fantasy_rosters where league_id = p_league_id)
      and (v_mode <> 'dynasty'
           or v_phase <> 'u20'
           or public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
      and (case p.position
             when 'gk'  then v_lim_gk  is null or v_cnt_gk  < v_lim_gk
             when 'def' then v_lim_def is null or v_cnt_def < v_lim_def
             when 'mid' then v_lim_mid is null or v_cnt_mid < v_lim_mid
             else            v_lim_fwd is null or v_cnt_fwd < v_lim_fwd
           end)
    order by q.rank limit 1;

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
        and (case p.position
               when 'gk'  then v_lim_gk  is null or v_cnt_gk  < v_lim_gk
               when 'def' then v_lim_def is null or v_cnt_def < v_lim_def
               when 'mid' then v_lim_mid is null or v_cnt_mid < v_lim_mid
               else            v_lim_fwd is null or v_cnt_fwd < v_lim_fwd
             end)
      order by
        (case when v_starter_phase then
           case p.position
             when 'gk'  then (case when v_cnt_gk  < v_tgt_gk  then 0 else 1 end)
             when 'def' then (case when v_cnt_def < v_tgt_def then 0 else 1 end)
             when 'mid' then (case when v_cnt_mid < v_tgt_mid then 0 else 1 end)
             else            (case when v_cnt_fwd < v_tgt_fwd then 0 else 1 end)
           end
         else
           case p.position
             when 'gk'  then 1000000
             when 'def' then (v_cnt_def - v_tgt_def)
             when 'mid' then (v_cnt_mid - v_tgt_mid)
             else            (v_cnt_fwd - v_tgt_fwd)
           end
         end) asc,
        (
          coalesce(t.appearances, 0) * v_w_app
        + coalesce(t.goals, 0) * (case p.position
            when 'gk'  then v_w_goal_gk
            when 'def' then v_w_goal_def
            when 'mid' then v_w_goal_mid
            else            v_w_goal_fwd end)
        + coalesce(t.assists, 0) * v_w_assist
        + (case p.position
             when 'gk'  then coalesce(t.clean_sheets, 0) * v_w_cs
             when 'def' then coalesce(t.clean_sheets, 0) * v_w_cs
             -- Neu: Das Mittelfeld bekommt 4 fuer die Null hinten. Ohne
             -- diese Zeile bewertete der Auto-Pick Sechser weiterhin so, als
             -- braechte sie ihnen nichts.
             when 'mid' then coalesce(t.clean_sheets, 0) * v_w_cs_mid
             else 0 end)
        + coalesce(t.yellow, 0) * v_w_yellow
        + coalesce(t.red, 0) * v_w_red
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
end$function$

;
