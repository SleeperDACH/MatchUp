-- Mehr Aufstellungen: die Formationsspannen werden geweitet.
--
-- Bis hier galt die enge FPL-Spanne (ABW 3–5, MF 2–5, ST 1–3). Daraus ergaben
-- sich genau **acht** Formationen — und drei gängige fehlten:
--
--   3-3-4, 4-2-4   (blockiert durch fwdMax 3)
--   3-6-1          (blockiert durch midMax 5)
--
-- Mit MF bis 6 und ST bis 4 sind es **elf**. Mindestens ein Stürmer bleibt
-- Pflicht (`fwdMin` 1): Eine Elf ohne Sturm wäre keine Formationslücke,
-- sondern eine Regeländerung.
--
-- **Nur nach oben, und nur wenn nötig** (`greatest`): Eine Liga, die ihre
-- Spanne bewusst weiter gesetzt hat, behält sie. Und eine weitere Spanne kann
-- keine gespeicherte Aufstellung ungültig machen — sie fügt Möglichkeiten
-- hinzu, sie nimmt keine weg. Deshalb ist das auch mitten in der Saison
-- unbedenklich.
--
-- Warum eine Migration und nicht nur neue Vorgabewerte im Client: Alle
-- bestehenden Ligen tragen die Spannen **ausgeschrieben** in
-- `fantasy_leagues.roster` (`RosterConfig.toJson` schreibt sie immer). Ein
-- geänderter Default in Dart hätte dort nichts bewirkt.

update fantasy_leagues
   set roster = roster || jsonb_build_object(
         'midMax', greatest(coalesce((roster->>'midMax')::int, 5), 6),
         'fwdMax', greatest(coalesce((roster->>'fwdMax')::int, 3), 4)
       )
 where roster is not null;

-- Die serverseitige Prüfung trägt dieselben Vorgaben für Ligen, denen die
-- Schlüssel ganz fehlen. `fantasy_set_lineup` bleibt sonst unverändert
-- (Migration 0084: Sperre je Spieler).
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
  v_mid_max := coalesce((v_roster->>'midMax')::int, 6);
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

  insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
  values (p_league_id, auth.uid(), v_season, p_round, p_player_ids)
  on conflict (league_id, manager_id, season, round)
    do update set player_ids = excluded.player_ids, updated_at = now();
end$$;
