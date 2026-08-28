-- Die Aufstellung sperrt je Spieler, nicht je Spieltag.
--
-- Bisher galt **ein** Riegel für alles: `fantasy_round_deadline` liefert den
-- frühesten Anpfiff der Runde, und ab dem nahm `fantasy_set_lineup` gar nichts
-- mehr an. Wer am Freitagabend das Eröffnungsspiel verpasst hatte, konnte auch
-- seinen Sonntagsspieler nicht mehr tauschen — obwohl der noch gar nicht
-- gespielt hatte. Das ist zwei Tage Sperre für null Informationsvorsprung.
--
-- Jetzt zählt der Anpfiff **des jeweiligen Spielers**. Geprüft wird nicht die
-- ganze Aufstellung, sondern nur, was sich **ändert**: Jeder Spieler, der
-- dazukommt oder herausfällt, muss noch spielfrei sein. Wer schon spielt oder
-- gespielt hat, ist festgenagelt — sonst könnte man einen Roten Karte
-- kassierenden Verteidiger nachträglich auf die Bank setzen.
--
-- Wichtig ist die Richtung: Ein Spieler, der **drin bleibt**, wird nicht
-- geprüft. Sonst wäre nach dem ersten Anpfiff jede Speicherung blockiert, denn
-- die unveränderten Spieler stehen ja weiter in der Liste — und damit hätten
-- wir die alte Sperre zurück, nur umständlicher.
--
-- **Kein Spiel gefunden, keine Sperre.** Der Kader kann Spieler enthalten,
-- deren Verein in dieser Runde nicht spielt (Pokal-Woche) oder gar nicht mehr
-- in der Liga ist — gemessen: von 19 Vereinen im Pool trifft genau einer
-- keinen Spielplan („AS Monaco", ein abgewanderter, noch gerosterter Spieler).
-- Solche Spieler zu bewegen bringt niemandem einen Vorteil: Sie punkten in
-- dieser Runde ohnehin nicht.
--
-- Die Zuordnung läuft über `players.club` = `fixtures.home_name`/`away_name`.
-- Das ist derselbe kanonische OpenLigaDB-Name, auf dem auch das Stats-Matching
-- steht (siehe CLAUDE.md); 18 von 19 Vereinen treffen exakt. `min(kickoff)`,
-- weil derselbe Spieltag doppelt gespiegelt sein kann (`openligadb:` und
-- `sportmonks:`) — die Anstoßzeit ist dann dieselbe.

create or replace function public.fantasy_spieler_anpfiff(
  p_season int, p_round int, p_player_id text
) returns timestamptz language sql stable as $$
  select min(f.kickoff)
    from players p
    join fixtures f
      on f.season = p_season and f.round = p_round
     and f.league_id = 'bundesliga'
     and (f.home_name = p.club or f.away_name = p.club)
   where p.id = p_player_id;
$$;

comment on function public.fantasy_spieler_anpfiff(int, int, text) is
  'Anpfiff des Spiels, in dem dieser Spieler an diesem Spieltag antritt; '
  'null, wenn sein Verein an dem Spieltag nicht spielt.';

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

  -- Bisher gespeicherte Elf; ohne Eintrag ist alles neu.
  select player_ids into v_alt
    from fantasy_lineups
   where league_id = p_league_id and manager_id = auth.uid()
     and season = v_season and round = p_round;
  v_alt := coalesce(v_alt, array[]::text[]);

  -- Nur die Änderung prüfen: rein oder raus.
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

  -- Nur Spieler aus dem eigenen Kader.
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
  v_fwd_max := coalesce((v_roster->>'fwdMax')::int, 3);

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
