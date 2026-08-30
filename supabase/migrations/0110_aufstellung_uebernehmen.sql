-- Die Aufstellung der Vorwoche wird uebernommen.
--
-- Ohne das beginnt jeder Spieltag bei null: Wer nicht in die App schaut, hat
-- **keine Elf** und damit keine Punkte. Nachgezaehlt zum Zeitpunkt dieser
-- Migration: 12 Aufstellungen fuer Spieltag 1, **eine** fuer Spieltag 2 — elf
-- Manager waeren leer in den naechsten Spieltag gegangen.
--
-- Es gibt keinen Aufstellungs-Autopick (`fantasy_autopick_all` gehoert dem
-- Draft), und die Oberflaeche zeigte die beste Elf nur als **Vorschlag**:
-- Gespeichert wurde erst, wenn jemand etwas anfasste. Wer den Schirm oeffnete
-- und wieder zumachte, weil ihm die Elf gefiel, hatte trotzdem nichts stehen.
--
-- Uebernommen wird die **letzte** Aufstellung des Managers vor dieser Runde,
-- nicht stur die der Vorrunde: Wer einen Spieltag ausgesetzt hat, faellt sonst
-- fuer immer aus der Uebernahme heraus.
--
-- Gefiltert wird auf den **aktuellen Kader**. Ein Spieler, der inzwischen weg
-- ist (Trade, Waiver, Drop), faellt raus und hinterlaesst einen leeren Platz —
-- besser als eine Elf, die den Server beim naechsten Speichern ablehnt.
--
-- **Nur wenn nichts dasteht.** Eine vorhandene Aufstellung wird nie
-- ueberschrieben, auch keine unvollstaendige.

create or replace function public.fantasy_aufstellung_uebernehmen()
returns int language plpgsql security definer set search_path to 'public' as $$
declare
  l record; v_runde int; v_zahl int; n int := 0;
begin
  for l in select id, season from fantasy_leagues where draft_status = 'done' loop
    v_runde := public.fantasy_laufende_runde(l.season);
    continue when v_runde is null or v_runde <= 1;

    insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
    select v.league_id, v.manager_id, v.season, v_runde,
           array(
             select pid from unnest(v.player_ids) as pid
              where exists (select 1 from fantasy_rosters r
                            where r.league_id = v.league_id
                              and r.manager_id = v.manager_id
                              and r.player_id = pid))
      from (
        -- Je Manager die juengste Aufstellung vor dieser Runde.
        select distinct on (a.manager_id) a.*
          from fantasy_lineups a
         where a.league_id = l.id and a.season = l.season and a.round < v_runde
           and cardinality(a.player_ids) > 0
         order by a.manager_id, a.round desc
      ) v
     where not exists (
             select 1 from fantasy_lineups vorhanden
              where vorhanden.league_id = v.league_id
                and vorhanden.manager_id = v.manager_id
                and vorhanden.season = v.season
                and vorhanden.round = v_runde)
       -- Verwaiste Teams brauchen keine Elf.
       and exists (select 1 from fantasy_league_members m
                    where m.league_id = v.league_id and m.user_id = v.manager_id
                      and not m.vacant);

    get diagnostics v_zahl = row_count;
    n := n + v_zahl;
  end loop;
  return n;
end$$;

select cron.unschedule('fantasy-aufstellung-uebernehmen')
 where exists (select 1 from cron.job where jobname = 'fantasy-aufstellung-uebernehmen');

select cron.schedule('fantasy-aufstellung-uebernehmen', '*/10 * * * *',
                     $$ select public.fantasy_aufstellung_uebernehmen(); $$);
