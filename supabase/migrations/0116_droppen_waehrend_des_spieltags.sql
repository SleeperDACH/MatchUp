-- Droppen und Traden gehen auch waehrend des Spieltags.
--
-- Vorgabe: *„Trotzdem kann man Spieler waehrend des Spieltags droppen oder
-- traden. Sie muessen dann nur trotzdem im MatchUp-Kader bleiben."*
--
-- Bis hierher verboten zwei Riegel genau das: `fantasy_drop_player` und
-- `fantasy_add_free_agent` warfen „Er steht in deiner Elf und sein Spiel
-- laeuft schon". Die gab es aus einem guten Grund — sie sollten verhindern,
-- dass ein Drop die Punkte eines laufenden Spieltags verschiebt.
--
-- **Diesen Grund gibt es seit 0115 nicht mehr.** Der Trigger auf
-- `fantasy_rosters` nimmt einen Spieler nur noch aus Aufstellungen, deren
-- Anpfiff fuer ihn **noch aussteht**; wer schon angepfiffen hat, bleibt in der
-- Elf und punktet dort weiter. Nachgemessen gilt das fuer jeden Weg, der eine
-- Kaderzeile loescht — Drop, Free-Agency-Tausch, Waiver-Zuteilung, Trade —,
-- weil der Riegel am Trigger haengt und nicht an der einzelnen Funktion.
--
-- Damit sind die beiden Ausnahmen nicht mehr Schutz, sondern nur noch eine
-- Einschraenkung ohne Zweck. Sie fallen weg.
--
-- `fantasy_steht_in_laufender_elf` bleibt bestehen: Die App fragt sie, um beim
-- Droppen den richtigen Hinweis zu zeigen.

create or replace function public.fantasy_drop_player(
  p_league_id uuid, p_player_id text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not exists (select 1 from fantasy_rosters
                 where league_id = p_league_id and player_id = p_player_id
                   and manager_id = auth.uid()) then
    raise exception 'Spieler ist nicht in deinem Kader';
  end if;

  -- **Kein Riegel mehr fuer die laufende Elf.** Steht er dort und hat sein
  -- Verein angepfiffen, bleibt er drin (Trigger aus 0115) — der Drop kostet
  -- ihn den Kaderplatz, nicht den Spieltag.
  delete from fantasy_rosters
    where league_id = p_league_id and player_id = p_player_id
      and manager_id = auth.uid();
  perform public.fantasy_put_on_wire(p_league_id, p_player_id);
end$$;

-- ---------------------------------------------------------------------------
-- Derselbe Riegel im Free-Agency-Tausch
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fantasy_add_free_agent(p_league_id uuid, p_add_player_id text, p_drop_player_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_season int; v_roster jsonb; v_locked boolean; v_count int;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  select season, roster into v_season, v_roster
    from fantasy_leagues where id = p_league_id for update;

  if not exists (select 1 from players where id = p_add_player_id) then
    raise exception 'Spieler unbekannt';
  end if;
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_add_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;
  -- **Ein Riegel statt zweier.** Vorher standen hier die 24-Stunden-Sperre und
  -- „sein Spiel laeuft" nebeneinander; jetzt beantwortet
  -- `fantasy_auf_dem_wire` beides — samt der Frist, die den Waiver eines
  -- Spieltags bis Montag 15:00 offen haelt.
  if public.fantasy_auf_dem_wire(p_league_id, v_season, p_add_player_id) then
    raise exception 'Er liegt auf dem Waiver – bitte per Antrag holen';
  end if;

  select public.fantasy_is_locked(birth_date, is_foreign_newcomer, v_season, now())
    into v_locked from players where id = p_add_player_id;
  if v_locked then
    raise exception 'Spieler ist gesperrt (U20/Neuzugang, für den U20-Draft reserviert)';
  end if;

  if p_drop_player_id is not null then
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and player_id = p_drop_player_id
                     and manager_id = auth.uid()) then
      raise exception 'Abzugebender Spieler ist nicht in deinem Kader';
    end if;
    -- **Kein Riegel mehr fuer die laufende Elf.** Hat sein Verein angepfiffen,
    -- bleibt er fuer diesen Spieltag in der Elf und punktet dort weiter
    -- (Trigger aus 0115); der Tausch kostet ihn nur den Kaderplatz.
    delete from fantasy_rosters
      where league_id = p_league_id and player_id = p_drop_player_id
        and manager_id = auth.uid();
    perform public.fantasy_put_on_wire(p_league_id, p_drop_player_id);
  end if;

  select count(*) into v_count from fantasy_rosters
    where league_id = p_league_id and manager_id = auth.uid();
  if v_count >= public.fantasy_squad_size(v_roster) then
    raise exception 'Kader voll – du musst einen Spieler abgeben';
  end if;

  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
  values (p_league_id, auth.uid(), p_add_player_id, 'fa');

end$function$

;
