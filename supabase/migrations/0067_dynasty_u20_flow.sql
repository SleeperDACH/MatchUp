-- Dynasty-Draft neu geordnet:
--  * Der Aufbau-Draft (Phase 'startup') draftet den KOMPLETTEN Kader aus
--    ALLEN Spielern — U20/Neuzugänge sind ganz normal wählbar.
--  * Danach läuft direkt die Saison. KEIN U20-Draft am Start.
--  * Der U20-Draft kommt erst mit dem Saison-Rollover (nächste Saison) und
--    wird über das neue Flag `u20_draft_pending` angeboten. Er draftet die
--    Rookies ZUSÄTZLICH (Kader wächst um u20_rounds); das Kürzen auf das
--    Limit erzwingt die Wertung separat.

alter table public.fantasy_leagues
  add column u20_draft_pending boolean not null default false;

-- Manueller Pick: im Aufbau-Draft sind jetzt ALLE Spieler wählbar (inkl. U20),
-- nur der U20-Draft bleibt auf Rookies beschränkt.
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
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_player_id) then
    raise exception 'Spieler ist bereits im Kader';
  end if;

  -- Nur im U20-Draft ist der Pool auf Rookies (U20/Auslands-Neuzugänge)
  -- beschränkt; im Aufbau-Draft ist alles wählbar.
  if v_mode = 'dynasty' and v_phase = 'u20' then
    select public.fantasy_is_rookie(birth_date, is_foreign_newcomer, v_season)
      into v_rookie from players where id = p_player_id;
    if not v_rookie then
      raise exception 'Im U20-Draft nur U20-Spieler und Auslands-Neuzugänge wählbar';
    end if;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, p_player_id, false);
end$$;

-- Auto-Pick: gleicher Phasen-Pool (Aufbau = alle, U20 = nur Rookies).
create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int; v_away boolean; v_expired boolean;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season
    into v_status, v_deadline, v_mode, v_phase, v_season
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;

  if auth.uid() is not null and not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  v_manager := public.fantasy_current_manager(p_league_id);
  select coalesce(auto_pick, false) into v_away
    from fantasy_league_members
    where league_id = p_league_id and user_id = v_manager;

  v_expired := v_deadline is not null and now() > v_deadline;
  if not v_expired and not coalesce(v_away, false) then return false; end if;

  -- Queue zuerst.
  select q.player_id into v_player
    from fantasy_draft_queue q join players p on p.id = q.player_id
    where q.league_id = p_league_id and q.manager_id = v_manager
      and q.player_id not in
          (select player_id from fantasy_rosters where league_id = p_league_id)
      and (v_mode <> 'dynasty'
           or v_phase <> 'u20'
           or public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
    order by q.rank limit 1;

  -- Rückfall: erster freier, phasen-gültiger Spieler.
  if v_player is null then
    select p.id into v_player from players p
      where p.id not in
            (select player_id from fantasy_rosters where league_id = p_league_id)
        and (v_mode <> 'dynasty'
             or v_phase <> 'u20'
             or public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
      order by p.name limit 1;
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

-- U20-Draft startet jetzt nur, wenn er per Rollover ansteht (Flag gesetzt) —
-- nicht mehr direkt nach dem Aufbau-Draft.
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

  update fantasy_leagues
    set draft_phase = 'u20', draft_status = 'drafting',
        picks_made = 0, u20_draft_pending = false,
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;

-- Saison-Rollover: jetzt aus jeder laufenden Saison möglich (Aufbau- ODER
-- U20-Draft abgeschlossen). Setzt das Flag, sodass danach der U20-Draft
-- angeboten wird; die Saison bleibt „done" (Kader bleibt bestehen).
create or replace function public.fantasy_rollover_season(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_mode text; v_season int;
begin
  select created_by, draft_status, mode, season
    into v_created_by, v_status, v_mode, v_season
    from fantasy_leagues where id = p_league_id for update;

  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann die Saison wechseln';
  end if;
  if v_mode <> 'dynasty' then
    raise exception 'Saison-Rollover nur im Dynasty-Modus';
  end if;
  if v_status <> 'done' then
    raise exception 'Die laufende Saison ist noch nicht abgeschlossen';
  end if;

  -- Draft-Verlauf leeren; die Kader (fantasy_rosters) bleiben bestehen.
  delete from draft_picks where league_id = p_league_id;

  -- Offene Waiver zurücksetzen.
  delete from fantasy_waiver_players where league_id = p_league_id;
  update fantasy_waiver_claims
    set status = 'invalid', reason = 'Saisonwechsel', processed_at = now()
    where league_id = p_league_id and status = 'pending';

  -- Neue Saison: der U20-Draft steht an (Flag), Saison bleibt „done".
  update fantasy_leagues
    set season = v_season + 1,
        u20_draft_pending = true,
        picks_made = 0,
        current_pick_deadline = null,
        draft_started_at = null
    where id = p_league_id;
end$$;
