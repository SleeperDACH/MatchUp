-- U20-Draft wie der Haupt-Draft: nach dem Saison-Rollover geht die Liga in
-- draft_status='setup' + draft_phase='u20'. Der Admin betritt den Draft-Raum
-- (Draft startet NICHT automatisch) und startet ihn dort über den
-- „Draft starten"-Button (start_u20_draft). So kann er vorher noch die
-- Reihenfolge prüfen/mischen.

-- Rollover: neue Saison, U20-Draft im Setup (statt sofort startbereit „done").
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

  -- Neue Saison: U20-Draft im Setup (der Admin startet ihn im Draft-Raum).
  update fantasy_leagues
    set season = v_season + 1,
        draft_status = 'setup',
        draft_phase = 'u20',
        u20_draft_pending = false,
        picks_made = 0,
        current_pick_deadline = null,
        draft_started_at = null
    where id = p_league_id;
end$$;

-- U20-Draft starten: nur aus dem Setup der U20-Phase (im Draft-Raum ausgelöst).
-- Setzt das Auto-Pick aus dem Aufbau-Draft zurück (0068) und beginnt zu draften.
create or replace function public.start_u20_draft(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_mode text; v_secs int; v_status text; v_phase text;
begin
  select created_by, mode, draft_pick_seconds, draft_status, draft_phase
    into v_created_by, v_mode, v_secs, v_status, v_phase
    from fantasy_leagues where id = p_league_id for update;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den U20-Draft starten';
  end if;
  if v_mode <> 'dynasty' then raise exception 'U20-Draft nur im Dynasty-Modus'; end if;
  if not (v_status = 'setup' and v_phase = 'u20') then
    raise exception 'Der U20-Draft ist nicht startbereit (erst nach dem Saison-Rollover)';
  end if;

  -- Auto-Pick aus dem Aufbau-Draft zurücksetzen — der U20-Draft startet normal.
  update fantasy_league_members set auto_pick = false
    where league_id = p_league_id;

  update fantasy_leagues
    set draft_status = 'drafting',
        picks_made = 0,
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;
