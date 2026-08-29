-- Die Prognose braucht einen Verein, den die App kennt.
--
-- Beim Anschluss der Oberflaeche fiel auf, dass die beiden Enden nicht
-- zusammenpassen: `predicted_lineups.fixture_id` traegt die **Sportmonks**-ID,
-- die App holt ihre Spielplaene aber von OpenLigaDB (`openligadb:<id>`,
-- fantasySeasonFixturesProvider). Ueber die Fixture-ID ist da nichts zu
-- verbinden — dieselbe Partie steht in `fixtures` zweimal, unter zwei IDs.
--
-- Verbunden wird deshalb ueber **Verein und Spieltag**, so wie es die
-- Aufstellungssperre (0084) schon macht. Dafuer braucht die Zeile den
-- kanonischen Vereinsnamen.
--
-- `team_sm_id` allein reicht nicht: In `fixtures` steht keine Sportmonks-
-- Team-ID, es gibt also keine Zuordnungstabelle. Der Sync loest den Verein
-- stattdessen ueber unseren eigenen Pool auf — von elf vorhergesagten Spielern
-- stehen praktisch immer mehrere in `players`, und deren `club` ist per
-- Definition der kanonische Name, auf dem auch das Stats-Matching steht.

alter table public.predicted_lineups
  add column if not exists club text;

create index if not exists predicted_lineups_club_idx
  on public.predicted_lineups (club);

-- Sicht mit Saison und Spieltag, damit die App nicht erst das Spiel
-- nachschlagen muss. `security_invoker` sorgt dafuer, dass die RLS der
-- Basistabellen gilt und nicht die Rechte des Eigentuemers.
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
  pf.formation,
  pl.updated_at
from public.predicted_lineups pl
join public.fixtures f on f.id = pl.fixture_id
left join public.predicted_formations pf
  on pf.fixture_id = pl.fixture_id
 and pf.team_sm_id = pl.team_sm_id;

grant select on public.predicted_lineups_v to authenticated, anon;
