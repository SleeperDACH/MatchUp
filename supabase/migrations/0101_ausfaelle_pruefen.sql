-- Ein Ausfall gilt nur, solange der Spieler nicht wieder gespielt hat.
--
-- **Die Quelle widerspricht sich selbst.** Gemessen an den 85 Ausfaellen aus
-- dem ersten Lauf: **neun** betreffen Spieler, die am 1. Spieltag 74 bis 90
-- Minuten auf dem Platz standen — Josha Vagnoman hat sogar getroffen und ist
-- dort seit Maerz 2025 als „Muscular problems" gefuehrt, Jeff Chabot seit
-- Maerz 2025 als „Ill". Ihr `completed`-Feld steht auf `false`, obwohl der
-- Ausfall offensichtlich vorbei ist.
--
-- Ein Symbol „verletzt" an einem Spieler, der gerade neunzig Minuten gemacht
-- hat, waere schlimmer als gar keins: Es sieht aus wie eine Auskunft.
--
-- Geprueft wird deshalb gegen **unsere eigenen Daten**: Hat der Spieler nach
-- dem Beginn des Ausfalls gespielt, ist der Ausfall ueberholt. Das ist keine
-- Schaetzung — Minuten in `player_match_stats` sind das Gegenteil von
-- „faellt aus".

create or replace view public.player_absences_v
with (security_invoker = true) as
with letzter_einsatz as (
  select s.player_id,
         max(f.kickoff) as gespielt_am
    from public.player_match_stats s
    join public.players p on p.id = s.player_id
    join public.fixtures f
      on f.season = s.season
     and f.round = s.round
     and f.league_id = 'bundesliga'
     and (f.home_name = p.club or f.away_name = p.club)
   where s.minutes > 0
   group by s.player_id
)
select
  a.id,
  a.player_id,
  a.kategorie,
  a.type_id,
  a.seit,
  a.bis,
  a.spiele_verpasst,
  a.updated_at,
  t.name as grund_quelle,
  e.gespielt_am,
  -- Ueberholt, wenn nach Beginn des Ausfalls ein Einsatz liegt.
  (e.gespielt_am is not null and a.seit is not null
     and e.gespielt_am::date > a.seit) as ueberholt
  from public.player_absences a
  left join public.sideline_types t on t.id = a.type_id
  left join letzter_einsatz e on e.player_id = a.player_id;

grant select on public.player_absences_v to authenticated, anon;
