-- Das Rasterfeld gehoert in die Sicht.
--
-- Die voraussichtliche Elf wird jetzt als Formation gezeigt, nicht als Liste.
-- Sportmonks liefert dafuer `formation_field` im Format "Reihe:Spalte" —
-- gemessen an Dortmund gegen HSV: Felix Nmecha steht auf "3:3", also dritte
-- Reihe (Mittelfeld der 3-4-2-1), dritte Position von links. Damit laesst
-- sich die Aufstellung genau so hinstellen, wie sie gemeint ist.
--
-- Die Alternative waere, die Formationszeichenkette ("3-4-2-1") zu zerlegen
-- und die Spieler nach `formation_position` in Bloecke zu schneiden. Das
-- ginge auch, raet aber, wo die Antwort schon danebensteht.

drop view if exists public.predicted_lineups_v;
create view public.predicted_lineups_v
with (security_invoker = true) as
select
  pl.fixture_id,
  f.season,
  f.round,
  f.kickoff,
  f.home_name,
  f.away_name,
  pl.club,
  pl.player_id,
  pl.player_name,
  pl.jersey_number,
  pl.formation_position,
  pl.formation_field,
  pf.formation,
  pl.updated_at
from public.predicted_lineups pl
join public.fixtures f on f.id = pl.fixture_id
left join public.predicted_formations pf
  on pf.fixture_id = pl.fixture_id
 and pf.team_sm_id = pl.team_sm_id;

grant select on public.predicted_lineups_v to authenticated, anon;
