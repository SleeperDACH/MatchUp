-- Die U20-Sperre gilt nur im Dynasty-Modus.
--
-- Gemeldet: „Es macht keinen Sinn, dass hier einer für den U20-Draft gesperrt
-- ist, weil es im Redraft-Modus keinen U20-Draft gibt. Das ist nur in
-- Dynasty."
--
-- Stimmt, und die Sperre stand trotzdem in **jeder** Liga. `fantasy_is_locked`
-- kennt Geburtsdatum, Auslands-Neuzugang und Saison — aber keine Liga, und
-- damit auch nicht deren Modus. Ab dem 5. September (Transferschluss) fiel
-- damit jeder U20-Spieler aus der Free Agency **auch dort, wo er nie wieder
-- gedraftet wird**: Im Redraft-Modus gibt es genau einen Draft, danach nie
-- einen zweiten. Der Spieler war für den Rest der Saison für niemanden mehr
-- zu holen, ohne dass es dafür einen Grund gab.
--
-- **Die Sperre bleibt, wo sie hingehört.** In Dynasty wird der Kader über
-- Saisons behalten, und die Rookies werden vor der neuen Saison neu gedraftet
-- — sie vorher per Free Agency wegzuschnappen, hebelte den U20-Draft aus.
--
-- `fantasy_is_locked` selbst bleibt unverändert: Sie beantwortet „ist dieser
-- Spieler ein reservierter Rookie?" und tut das richtig. Was fehlte, war die
-- Frage davor — „gilt diese Reservierung in dieser Liga überhaupt?".

create or replace function public.fantasy_u20_gesperrt(
  p_league_id uuid, p_player_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select l.mode = 'dynasty'
     and public.fantasy_is_locked(
           p.birth_date, p.is_foreign_newcomer, l.season, now())
    from fantasy_leagues l, players p
   where l.id = p_league_id and p.id = p_player_id;
$$;

grant execute on function public.fantasy_u20_gesperrt(uuid, text)
  to authenticated;

CREATE OR REPLACE FUNCTION public.fantasy_add_free_agent(p_league_id uuid, p_add_player_id text, p_drop_player_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_season int; v_roster jsonb; v_count int;
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

  -- Nur in Dynasty: Im Redraft-Modus gibt es keinen zweiten Draft, für den
  -- man jemanden reservieren könnte.
  if public.fantasy_u20_gesperrt(p_league_id, p_add_player_id) then
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

end$function$;

CREATE OR REPLACE FUNCTION public.fantasy_submit_waiver_claim(p_league_id uuid, p_add_player_id text, p_drop_player_id text DEFAULT NULL::text, p_rank integer DEFAULT 1)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_season int; v_id uuid;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  select season into v_season from fantasy_leagues where id = p_league_id;

  -- Beantragbar ist, wer auf dem Waiver liegt: ausdruecklich gedroppt oder
  -- sein Verein hat angepfiffen und die Frist ist noch nicht erreicht. Wer
  -- frei und abholbar ist, braucht keinen Antrag — den nimmt man einfach.
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_add_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;
  if not public.fantasy_auf_dem_wire(p_league_id, v_season, p_add_player_id) then
    raise exception 'Spieler ist frei – du kannst ihn direkt holen';
  end if;

  if public.fantasy_u20_gesperrt(p_league_id, p_add_player_id) then
    raise exception 'Spieler ist gesperrt (U20/Neuzugang)';
  end if;

  if p_drop_player_id is not null and not exists (
       select 1 from fantasy_rosters
       where league_id = p_league_id and player_id = p_drop_player_id
         and manager_id = auth.uid()) then
    raise exception 'Abzugebender Spieler ist nicht in deinem Kader';
  end if;

  insert into fantasy_waiver_claims
    (league_id, manager_id, add_player_id, drop_player_id, rank)
  values
    (p_league_id, auth.uid(), p_add_player_id, p_drop_player_id, greatest(p_rank, 1))
  returning id into v_id;
  return v_id;
end$function$;
