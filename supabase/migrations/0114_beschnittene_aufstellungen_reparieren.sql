-- Nachtrag zu 0113: die Reparatur griff nicht.
--
-- Sie verglich die fehlenden Plaetze gegen `fantasy_squad_size` — das ist der
-- **ganze Kader** (16), nicht die Startelf (11). Damit fehlten rechnerisch
-- sechs Plaetze bei einem Abgang, die Eindeutigkeitspruefung schlug fehl, und
-- es wurde nichts wiederhergestellt. Der Filter war zu streng statt falsch;
-- der Schaden blieb, aber es wurde auch nichts Falsches geschrieben.
--
-- Dafuer gibt es jetzt einen eigenen Helfer: Die Startelf ist die Kadergroesse
-- **ohne Bank**, und dass diese Zahl an zwei Stellen verschieden gerechnet
-- wurde, war der ganze Fehler.

create or replace function public.fantasy_startelf_groesse(p_roster jsonb)
returns int language sql immutable as $$
  select coalesce((p_roster->>'gk')::int, 1)
       + coalesce((p_roster->>'def')::int, 4)
       + coalesce((p_roster->>'mid')::int, 4)
       + coalesce((p_roster->>'fwd')::int, 2);
$$;

with beschnitten as (
  select fl.league_id, fl.manager_id, fl.season, fl.round, fl.updated_at,
         public.fantasy_startelf_groesse(l.roster)
           - cardinality(fl.player_ids) as fehlen,
         fl.player_ids
    from fantasy_lineups fl
    join fantasy_leagues l on l.id = fl.league_id
   where cardinality(fl.player_ids) between 1 and 10
     and public.fantasy_runde_angepfiffen(fl.season, fl.round)
),
kandidaten as (
  select b.league_id, b.manager_id, b.season, b.round, b.fehlen,
         array_agg(rm.player_id) as weg
    from beschnitten b
    join fantasy_roster_moves rm
      on rm.league_id = b.league_id and rm.manager_id = b.manager_id
     and rm.richtung = 'abgang' and rm.passiert_am < b.updated_at
   group by 1,2,3,4,5
)
update fantasy_lineups fl
   set player_ids = fl.player_ids || k.weg,
       updated_at = now()
  from kandidaten k
 where fl.league_id = k.league_id and fl.manager_id = k.manager_id
   and fl.season = k.season and fl.round = k.round
   -- **Nur das Eindeutige.** So viele Abgaenge wie fehlende Plaetze: dann ist
   -- klar, wer zurueckgehoert. Sonst bleibt die Elf, wie sie ist — raten waere
   -- schlimmer als eine Luecke, die man sieht.
   and cardinality(k.weg) = k.fehlen;
