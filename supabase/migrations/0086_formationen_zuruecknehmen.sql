-- 3-3-4 und 3-6-1 wieder entfernen, 4-2-4 behalten.
--
-- Migration 0085 hatte die Spannen auf MF 2–6 und ST 1–4 geweitet und damit
-- drei Formationen ergänzt: 3-3-4, 4-2-4 und 3-6-1. Zwei davon sind auf
-- ausdrücklichen Wunsch wieder weg, die dritte bleibt. Ergebnis: **neun**
-- Formationen (die ursprünglichen acht plus 4-2-4).
--
-- **3-6-1 geht sauber über die Spanne** — `midMax` zurück auf 5, und es ist die
-- einzige Formation mit sechs Mittelfeldspielern.
--
-- **3-3-4 geht so nicht.** 3-3-4 und 4-2-4 brauchen beide `fwdMax` 4 und
-- unterscheiden sich nur in der Abwehr; reine Min/Max-Spannen können das eine
-- nicht ohne das andere entfernen. Es braucht eine Regel, die zwei Positionen
-- **zugleich** anschaut:
--
--   Vier Stürmer nur mit mindestens vier Abwehrspielern.
--
-- Dieselbe Regel steht ein zweites Mal in Dart
-- (`RosterConfig.vierStuermerBrauchenVierAbwehr`) — bewusste Doppelung wie bei
-- `tip_scoring.dart` ↔ SQL-View. Laufen die beiden auseinander, bietet die App
-- eine Formation an, die der Server ablehnt.
--
-- **Die Verengung entwertet nichts:** Nachgemessen vor dem Einspielen — keine
-- einzige gespeicherte Aufstellung nutzt sechs Mittelfeldspieler oder vier
-- Stürmer bei drei Abwehrspielern. Die Weitung stand auch erst seit einer
-- knappen Stunde und war noch in keinem Build.

update fantasy_leagues
   set roster = roster || jsonb_build_object(
         'midMax', least(coalesce((roster->>'midMax')::int, 5), 5)
       )
 where roster is not null;

create or replace function public.fantasy_set_lineup(
  p_league_id uuid, p_round integer, p_player_ids text[]
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_roster jsonb;
  v_gk int; v_def int; v_mid int; v_fwd int;
  v_gk_slots int; v_starters int;
  v_def_min int; v_def_max int; v_mid_min int; v_mid_max int;
  v_fwd_min int; v_fwd_max int;
  v_alt text[]; v_pid text; v_kick timestamptz; v_name text;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  select season, roster into v_season, v_roster
    from fantasy_leagues where id = p_league_id;

  select player_ids into v_alt
    from fantasy_lineups
   where league_id = p_league_id and manager_id = auth.uid()
     and season = v_season and round = p_round;
  v_alt := coalesce(v_alt, array[]::text[]);

  -- Nur die Änderung prüfen: rein oder raus (siehe 0084).
  for v_pid in
    (select unnest(p_player_ids) except select unnest(v_alt))
    union
    (select unnest(v_alt) except select unnest(p_player_ids))
  loop
    v_kick := public.fantasy_spieler_anpfiff(v_season, p_round, v_pid);
    if v_kick is not null and now() >= v_kick then
      select name into v_name from players where id = v_pid;
      raise exception 'Zu spät für %: Sein Spiel läuft schon.',
        coalesce(v_name, v_pid);
    end if;
  end loop;

  if exists (
    select 1 from unnest(p_player_ids) pid
    where not exists (
      select 1 from fantasy_rosters r
      where r.league_id = p_league_id and r.manager_id = auth.uid()
        and r.player_id = pid)) then
    raise exception 'Aufstellung enthält Spieler außerhalb deines Kaders';
  end if;

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
  v_fwd_max := coalesce((v_roster->>'fwdMax')::int, 4);

  select count(*) filter (where p.position = 'gk'),
         count(*) filter (where p.position = 'def'),
         count(*) filter (where p.position = 'mid'),
         count(*) filter (where p.position = 'fwd')
    into v_gk, v_def, v_mid, v_fwd
    from players p where p.id = any(p_player_ids);

  if coalesce(array_length(p_player_ids, 1), 0) <> v_starters then
    raise exception 'Aufstellung braucht genau % Spieler', v_starters;
  end if;

  if v_gk <> v_gk_slots
   or v_def < v_def_min or v_def > v_def_max
   or v_mid < v_mid_min or v_mid > v_mid_max
   or v_fwd < v_fwd_min or v_fwd > v_fwd_max then
    raise exception 'Aufstellung verletzt die Formation (% TW / % ABW / % MF / % ST)',
      v_gk, v_def, v_mid, v_fwd;
  end if;

  -- Gekoppelte Regel, siehe Kopfkommentar: 3-3-4 fällt weg, 4-2-4 bleibt.
  if v_fwd >= 4 and v_def < 4 then
    raise exception
      'Vier Stürmer nur mit mindestens vier Abwehrspielern (% ABW / % ST)',
      v_def, v_fwd;
  end if;

  insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
  values (p_league_id, auth.uid(), v_season, p_round, p_player_ids)
  on conflict (league_id, manager_id, season, round)
    do update set player_ids = excluded.player_ids, updated_at = now();
end$$;
