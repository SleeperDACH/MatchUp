-- Saison-Rollover (Dynasty, Phase 3+): eine Dynasty-Liga in die nächste
-- Saison überführen.
--
-- Mechanik (Nutzerentscheidung „kompletter Kader / Abgänge behalten"):
--   * Der komplette Kader bleibt erhalten (fantasy_rosters wird nicht
--     angefasst) — auch Spieler, die nicht mehr im aktuellen Pool sind.
--   * Es wird KEIN neuer Haupt-Draft gefahren; nur ein frischer U20-Draft
--     für die neuen Rookies der neuen Saison (Alter < 20 zum 1. Spieltag
--     bzw. Auslands-Neuzugänge).
--   * Der alte Draft-Verlauf (draft_picks) wird geleert — die Kader stecken
--     bereits in fantasy_rosters (Trigger draft_picks_to_roster). So kollidiert
--     die neue U20-Runde nicht mit den Pick-Nummern der Vorsaison.
--   * Offene Waiver werden zurückgesetzt; Lineups sind je Saison eigene Zeilen
--     und bleiben als Historie stehen.
--
-- Zustand nach dem Rollover: draft_status = 'done', draft_phase = 'startup'
-- (die Vorbedingung von start_u20_draft) — der Ersteller startet dann über
-- den bestehenden „U20-Draft starten"-Button die neue Rookie-Runde.

-- ---------------------------------------------------------------------
-- Pick-Pool jetzt anhand des Kaders (fantasy_rosters) statt der Draft-
-- Historie (draft_picks). Nötig, weil der Rollover draft_picks leert:
-- danach ist der Kader die einzige verlässliche „schon vergeben"-Menge.
-- Der Trigger draft_picks_to_roster schreibt jeden Pick sofort in den
-- Kader, daher bleibt der laufende Draft (Haupt wie U20) korrekt.
-- ---------------------------------------------------------------------

-- Manueller Pick mit Phasen-Pool-Prüfung (nur Dynasty).
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

  if v_mode = 'dynasty' then
    select public.fantasy_is_rookie(birth_date, is_foreign_newcomer, v_season)
      into v_rookie from players where id = p_player_id;
    if v_phase = 'startup' and v_rookie then
      raise exception 'Im Haupt-Draft nur etablierte Spieler (U20/Neuzugänge folgen im U20-Draft)';
    end if;
    if v_phase = 'u20' and not v_rookie then
      raise exception 'Im U20-Draft nur U20-Spieler und Auslands-Neuzugänge wählbar';
    end if;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, p_player_id, false);
end$$;

-- Auto-Pick respektiert den Phasen-Pool und meidet bereits gerosterte Spieler.
create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season
    into v_status, v_deadline, v_mode, v_phase, v_season
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;
  if v_deadline is null or now() <= v_deadline then return false; end if;

  if auth.uid() is not null and not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  v_manager := public.fantasy_current_manager(p_league_id);

  select p.id into v_player from players p
    where p.id not in (select player_id from fantasy_rosters where league_id = p_league_id)
      and (v_mode <> 'dynasty'
           or (v_phase = 'u20')
              = public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
    order by p.name limit 1;

  if v_player is null then
    update fantasy_leagues
      set draft_status = 'done', current_pick_deadline = null
      where id = p_league_id;
    return false;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, v_player, true);
  return true;
end$$;

-- ---------------------------------------------------------------------
-- Rollover in die neue Saison.
-- ---------------------------------------------------------------------
create function public.fantasy_rollover_season(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_phase text; v_mode text; v_season int;
begin
  select created_by, draft_status, draft_phase, mode, season
    into v_created_by, v_status, v_phase, v_mode, v_season
    from fantasy_leagues where id = p_league_id for update;

  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann die Saison wechseln';
  end if;
  if v_mode <> 'dynasty' then
    raise exception 'Saison-Rollover nur im Dynasty-Modus';
  end if;
  -- Erst nach vollständig abgeschlossener Saison (U20-Draft beendet).
  if not (v_status = 'done' and v_phase = 'u20') then
    raise exception 'Die Saison ist noch nicht abgeschlossen (U20-Draft muss erst beendet sein)';
  end if;

  -- Draft-Verlauf leeren; die Kader (fantasy_rosters) bleiben bestehen.
  delete from draft_picks where league_id = p_league_id;

  -- Offene Waiver zurücksetzen: den Wire leeren, laufende Anträge entwerten.
  delete from fantasy_waiver_players where league_id = p_league_id;
  update fantasy_waiver_claims
    set status = 'invalid', reason = 'Saisonwechsel', processed_at = now()
    where league_id = p_league_id and status = 'pending';

  -- Neue Saison: bereit für den nächsten U20-Draft (start_u20_draft-Vorbedingung).
  update fantasy_leagues
    set season = v_season + 1,
        draft_phase = 'startup',
        draft_status = 'done',
        picks_made = 0,
        current_pick_deadline = null,
        draft_started_at = null
    where id = p_league_id;
end$$;
