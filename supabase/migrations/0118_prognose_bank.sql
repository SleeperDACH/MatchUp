-- Die Bank gehoert zur Aufstellung.
--
-- Gewuenscht: „Bei der voraussichtlichen Aufstellung bitte auch die Bank
-- anzeigen." Die Prognose selbst gibt sie nicht her — **gemessen am
-- 02.09.2026** liefert `predictedLineups` fuer beide gepruefte Partien genau
-- 22 Eintraege, elf je Mannschaft, alle mit demselben `type_id` 111384. Eine
-- vorhergesagte Bank gibt es bei Sportmonks nicht.
--
-- Es gibt sie aber, sobald die Vereine ihre Aufstellung melden: Der Include
-- `lineups` traegt am selben Spiel `type_id` 11 (Startelf) und 12 (Bank) —
-- fuer Leverkusen gegen Elversberg 22 plus 18 Eintraege, und beide kommen im
-- selben `fixtures/multi`-Request mit, den der Sync ohnehin stellt (gemessen:
-- `remaining` sinkt um 1). Fuer ein noch nicht angesetztes Spiel ist die
-- Liste leer — sie kann die Prognose also nicht zu frueh verdraengen.
--
-- Daraus die Regel: **Was gemeldet ist, schlaegt was vorhergesagt ist.**
-- Solange nur die Prognose steht, zeigt die App elf Namen und sagt, dass die
-- Bank erst mit der offiziellen Aufstellung kommt. Danach steht dieselbe
-- Ansicht auf der echten Elf und der echten Bank.
--
-- Zwei Spalten statt einer zweiten Tabelle: Die Zeilen sind dieselben (Spiel,
-- Spieler, Nummer, Rasterplatz), es unterscheidet sie nur, ob sie sitzen und
-- ob sie geraten sind.

alter table public.predicted_lineups
  add column if not exists bank boolean not null default false;

-- Woher die Zeile kommt: false = Prognose (`predictedLineups`), true = die
-- gemeldete Aufstellung (`lineups`). Die App schreibt damit „Voraussichtlich"
-- oder „Offiziell" ueber dieselbe Ansicht.
alter table public.predicted_lineups
  add column if not exists bestaetigt boolean not null default false;

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
  pl.bank,
  pl.bestaetigt,
  pf.formation,
  pl.updated_at
from public.predicted_lineups pl
join public.fixtures f on f.id = pl.fixture_id
left join public.predicted_formations pf
  on pf.fixture_id = pl.fixture_id
 and pf.team_sm_id = pl.team_sm_id;

grant select on public.predicted_lineups_v to authenticated, anon;
