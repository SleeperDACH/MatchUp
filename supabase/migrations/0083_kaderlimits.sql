-- Kader-Limits je Position.
--
-- Anlass aus der laufenden Liga: Ein Manager hatte **acht Stürmer und drei
-- Abwehrspieler**. Mit der Formationsspanne (ABW 3–5, ST 1–3) konnte er genau
-- eine Aufstellung stellen, 1-3-4-3; fällt einer der drei Verteidiger aus,
-- bekommt er gar keine gültige Elf mehr zusammen. Fünf Kaderplätze waren tot.
--
-- Die Limits liegen als `maxGk` / `maxDef` / `maxMid` / `maxFwd` in der
-- `roster`-JSONB der Liga. **Fehlt ein Schlüssel, gilt kein Limit** — das ist
-- Absicht: Zwei Drafts liefen, als das hier entstand, und eine stillschweigend
-- eingeführte Obergrenze hätte sie mitten im Lauf blockieren können. Wer
-- Limits will, setzt sie in den Liga-Einstellungen.
--
-- **Bestehende Kader brechen nicht.** Der Trigger prüft nur beim Hinzufügen;
-- wer schon über dem Limit liegt, behält seine Spieler und kann auf dieser
-- Position nur nichts mehr dazunehmen. Rückwirkend Spieler wegzunehmen wäre
-- keine Regel, sondern eine Enteignung.
--
-- **Warum ein Trigger und keine sechs Funktionen:** Spieler kommen über
-- `fantasy_make_pick`, den Auto-Pick (`fantasy_advance`),
-- `fantasy_add_free_agent`, `fantasy_process_waivers`, `fantasy_admin_add` und
-- `fantasy_respond_trade` in einen Kader. Sechs Stellen sind sechs
-- Gelegenheiten, eine zu vergessen — und der siebte Weg, den jemand nächstes
-- Jahr baut, wäre von vornherein außen vor. Der Trigger sitzt an der einzigen
-- Stelle, an der alle vorbeikommen: der Tabelle.
--
-- Trades laufen über ein **`update` von `manager_id`**, nicht über
-- Delete+Insert — deshalb hängt der Trigger an `insert or update`.

-- Limit einer Liga für eine Position; null = unbegrenzt.
create or replace function public.fantasy_kaderlimit(
  p_league_id uuid, p_position text
) returns numeric language sql stable as $$
  select public.fantasy_num(
    l.roster,
    case p_position
      when 'gk'  then 'maxGk'
      when 'def' then 'maxDef'
      when 'mid' then 'maxMid'
      else            'maxFwd'
    end,
    null)
  from fantasy_leagues l where l.id = p_league_id;
$$;

comment on function public.fantasy_kaderlimit(uuid, text) is
  'Obergrenze an Kaderspielern dieser Position; null bedeutet unbegrenzt. '
  'Liest maxGk/maxDef/maxMid/maxFwd aus fantasy_leagues.roster.';

create or replace function public.fantasy_kaderlimit_pruefen()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pos text; v_limit numeric; v_anzahl int; v_name text;
begin
  -- Beim Update nur prüfen, wenn der Spieler den Besitzer wechselt.
  if tg_op = 'UPDATE' and new.manager_id is not distinct from old.manager_id then
    return new;
  end if;

  select position into v_pos from players where id = new.player_id;
  if v_pos is null then return new; end if;

  v_limit := public.fantasy_kaderlimit(new.league_id, v_pos);
  if v_limit is null then return new; end if;

  select count(*) into v_anzahl
    from fantasy_rosters r join players p on p.id = r.player_id
   where r.league_id = new.league_id
     and r.manager_id = new.manager_id
     and p.position = v_pos
     and r.player_id <> new.player_id;

  if v_anzahl >= v_limit then
    v_name := case v_pos
                when 'gk'  then 'Torhüter'
                when 'def' then 'Abwehrspieler'
                when 'mid' then 'Mittelfeldspieler'
                else            'Stürmer'
              end;
    raise exception
      'Kader-Limit erreicht: höchstens % % in dieser Liga', v_limit::int, v_name;
  end if;
  return new;
end$$;

drop trigger if exists fantasy_rosters_kaderlimit on public.fantasy_rosters;
create trigger fantasy_rosters_kaderlimit
  before insert or update on public.fantasy_rosters
  for each row execute function public.fantasy_kaderlimit_pruefen();

-- Der Auto-Pick muss volle Positionen überspringen.
--
-- Sonst zöge er nach seiner Rangliste einen Stürmer, der Trigger wirft, und
-- der Draft steht — genau der Zustand, den 0079 gerade beseitigt hat. Der
-- Filter sitzt deshalb **in der Auswahl**, nicht als nachträgliche Prüfung:
-- Ein Spieler auf einer vollen Position ist für diesen Manager schlicht nicht
-- wählbar, auch nicht aus seiner Wunschliste.
--
-- Bleibt dadurch kein Spieler übrig, endet der Draft (`draft_status = 'done'`)
-- — deshalb muss die Oberfläche verhindern, dass die Summe der Limits unter
-- die Kadergröße fällt. Eine Liga mit 16 Runden und Limits, die zusammen 12
-- ergeben, wäre nicht streng, sondern kaputt.

create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int; v_away boolean; v_expired boolean;
  v_scoring jsonb; v_last_season int; v_roster jsonb;
  v_tgt_gk int; v_tgt_def int; v_tgt_mid int; v_tgt_fwd int;
  v_cnt_gk int; v_cnt_def int; v_cnt_mid int; v_cnt_fwd int;
  v_starter_phase boolean; v_v2 boolean;
  v_lim_gk numeric; v_lim_def numeric; v_lim_mid numeric; v_lim_fwd numeric;
  v_w_app numeric; v_w_assist numeric; v_w_cs numeric;
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
        + (case when p.position in ('gk', 'def')
                then coalesce(t.clean_sheets, 0) * v_w_cs
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
end$$;
