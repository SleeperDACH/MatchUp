-- Die letzten beiden Fantasy-Funktionen lesen den Spielplan ebenfalls nur noch
-- aus einer Quelle.
--
-- 0107 hat den doppelten Spielplan aufgeraeumt und die Runden-Funktionen auf
-- `sportmonks:` gefiltert. Diese zwei standen noch ohne Filter da. Sie rechnen
-- ueber ganze Runden statt ueber Vereinsnamen und waren deshalb nicht kaputt —
-- aber ein halber Filter ist genau die Sorte Inkonsequenz, die beim naechsten
-- Altbestand wieder eine Woche kostet. `fantasy_trade_frei_ab` haette mit den
-- alten Zeilen jede Runde fuer „laeuft noch" gehalten und Trades dauerhaft
-- zurueckgehalten.

create or replace function public.fantasy_round_deadline(p_season int, p_round int)
returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select min(kickoff) from public.fixtures
   where league_id = 'bundesliga' and season = p_season and round = p_round
     and id like 'sportmonks:%';
$$;

CREATE OR REPLACE FUNCTION public.fantasy_trade_frei_ab(p_league_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_season int; v_letzter timestamptz;
begin
  select season into v_season from fantasy_leagues where id = p_league_id;
  if v_season is null then return now(); end if;

  -- Die Runde, die gerade läuft: erster Anpfiff vorbei, noch nicht alle
  -- Partien beendet. Gibt es keine, läuft kein Spieltag.
  select max(f.kickoff) into v_letzter
    from fixtures f
   where f.league_id = 'bundesliga'
     and f.id like 'sportmonks:%'
     and f.season = v_season
     and f.round = (
       select f2.round from fixtures f2
        where f2.league_id = 'bundesliga' and f2.season = v_season
          and f2.id like 'sportmonks:%'
        group by f2.round
       having min(f2.kickoff) <= now()
          and bool_or(f2.status <> 'finished')
        order by min(f2.kickoff) desc
        limit 1
     );

  if v_letzter is null then return now(); end if;
  -- 2 h Spieldauer, dann die zwölf Stunden Schonfrist.
  return greatest(now(), v_letzter + interval '2 hours' + interval '12 hours');
end$function$

;
