-- Flexible Formation (Phase 5b): Die Startelf ist nicht mehr an eine feste
-- Formation gebunden, sondern an Min/Max je Position aus der roster-Konfig
-- (FPL-Stil: ABW 3–5, MF 2–5, ST 1–3, Torwart genau 1, Summe = 11).
--
-- Bisher (0008): pro Position höchstens die Slot-Anzahl, Unterbesetzen
-- erlaubt. Jetzt: genau `starters` Spieler in einer gültigen Formation.
-- Defaults greifen, falls die roster-JSONB die Grenzen (noch) nicht enthält
-- — Bestandsligen bleiben so kompatibel.
--
-- Spiegelbild zur Client-Logik in RosterConfig.isValidFormation /
-- bestEleven (lib/features/fantasy) — bei Änderungen beide anpassen.

create or replace function public.fantasy_set_lineup(
  p_league_id uuid, p_round int, p_player_ids text[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_roster jsonb; v_deadline timestamptz;
  v_gk int; v_def int; v_mid int; v_fwd int;
  v_gk_slots int; v_starters int;
  v_def_min int; v_def_max int; v_mid_min int; v_mid_max int;
  v_fwd_min int; v_fwd_max int;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  select season, roster into v_season, v_roster
    from fantasy_leagues where id = p_league_id;

  v_deadline := public.fantasy_round_deadline(v_season, p_round);
  if v_deadline is not null and now() >= v_deadline then
    raise exception 'Aufstellung ist gesperrt – der Spieltag hat begonnen';
  end if;

  -- Nur Spieler aus dem eigenen Kader.
  if exists (
    select 1 from unnest(p_player_ids) pid
    where not exists (
      select 1 from fantasy_rosters r
      where r.league_id = p_league_id and r.manager_id = auth.uid()
        and r.player_id = pid)) then
    raise exception 'Aufstellung enthält Spieler außerhalb deines Kaders';
  end if;

  -- Formations-Grenzen aus der roster-Konfig (mit FPL-Defaults).
  v_gk_slots := coalesce((v_roster->>'gk')::int, 1);
  v_starters := v_gk_slots
              + coalesce((v_roster->>'def')::int, 4)
              + coalesce((v_roster->>'mid')::int, 4)
              + coalesce((v_roster->>'fwd')::int, 2);
  v_def_min := coalesce((v_roster->>'defMin')::int, 3);
  v_def_max := coalesce((v_roster->>'defMax')::int, 5);
  v_mid_min := coalesce((v_roster->>'midMin')::int, 2);
  v_mid_max := coalesce((v_roster->>'midMax')::int, 5);
  v_fwd_min := coalesce((v_roster->>'fwdMin')::int, 1);
  v_fwd_max := coalesce((v_roster->>'fwdMax')::int, 3);

  select count(*) filter (where p.position = 'gk'),
         count(*) filter (where p.position = 'def'),
         count(*) filter (where p.position = 'mid'),
         count(*) filter (where p.position = 'fwd')
    into v_gk, v_def, v_mid, v_fwd
    from players p where p.id = any(p_player_ids);

  -- Genau die Startelf-Größe.
  if coalesce(array_length(p_player_ids, 1), 0) <> v_starters then
    raise exception 'Aufstellung braucht genau % Spieler', v_starters;
  end if;

  -- Gültige Formation: Torwart exakt, Feldspieler in ihrer Spanne.
  if v_gk <> v_gk_slots
   or v_def < v_def_min or v_def > v_def_max
   or v_mid < v_mid_min or v_mid > v_mid_max
   or v_fwd < v_fwd_min or v_fwd > v_fwd_max then
    raise exception 'Aufstellung verletzt die Formation (% TW / % ABW / % MF / % ST)',
      v_gk, v_def, v_mid, v_fwd;
  end if;

  insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
  values (p_league_id, auth.uid(), v_season, p_round, p_player_ids)
  on conflict (league_id, manager_id, season, round)
    do update set player_ids = excluded.player_ids, updated_at = now();
end$$;
