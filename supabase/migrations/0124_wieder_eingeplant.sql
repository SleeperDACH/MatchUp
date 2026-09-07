-- Wieder fit heisst wieder fit, auch ohne Einsatz.
--
-- Eingewandt: „Wenn der Spieler den Eintrag hat, nur weil er verletzt
-- ausgewechselt wurde, und dann aber wieder fit ist in der Woche, wird er als
-- verletzt angezeigt, obwohl das falsch ist."
--
-- Stimmt, und es trifft genau die Woche, in der man die Aufstellung macht.
-- 0122 loeste den abgeleiteten Eintrag erst auf, wenn der Spieler **wieder
-- Minuten gemacht** hat -- also fruehestens waehrend des naechsten Spiels.
-- Bis dahin stand die Vermutung, auch wenn der Verein ihn laengst wieder
-- eingeplant hatte.
--
-- **Die Aufstellung weiss es frueher.** `predicted_lineups` traegt ein bis
-- zwei Tage vor Anpfiff die voraussichtliche Elf und, sobald gemeldet, die
-- echte samt Bank (576 Zeilen ueber 18 Spiele, Stand 07.09.2026). Wer dort
-- fuer ein spaeteres Spiel steht -- in der Elf **oder auf der Bank** --, ist
-- offensichtlich fit; die Bank zaehlt mit, denn auf sie setzt niemand einen
-- Verletzten.
--
-- Damit loest sich die Vermutung zum spaetestmoeglichen ehrlichen Zeitpunkt
-- auf: nicht erst nach dem Anpfiff, sondern sobald der Verein seine Absicht
-- zeigt. Was bleibt, ist die Luecke zwischen Abpfiff und Prognose -- dort gibt
-- es schlicht keine neue Auskunft, und der Eintrag sagt deshalb „vermutlich".
create or replace view public.player_absences_v
with (security_invoker = true) as
with letzter_einsatz as (
  select s.player_id, max(f.kickoff) as gespielt_am, max(s.round) as letzte_runde
    from player_match_stats s
    join players p on p.id = s.player_id
    join fixtures f
      on f.season = s.season
     and f.round = s.round
     and f.league_id = 'bundesliga'
     and (fantasy_verein_kanonisch(f.home_name) = fantasy_verein_kanonisch(p.club)
       or fantasy_verein_kanonisch(f.away_name) = fantasy_verein_kanonisch(p.club))
   where s.minutes > 0
   group by s.player_id
), saisonstart as (
  select min(f.kickoff)::date as tag
    from fixtures f
   where f.league_id = 'bundesliga'
     and f.season = (select max(season) from fixtures where league_id = 'bundesliga')
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
  'gemeldet'::text as quelle,
  null::int as runde,
  null::int as minute,
  -- „Gilt fuer die Bundesliga nicht (mehr)": drei Gruende, drei Zeilen.
  (e.gespielt_am is not null and a.seit is not null and e.gespielt_am::date > a.seit)
    or (a.kategorie = 'suspended' and a.seit is not null
        and a.seit < (select tag from saisonstart))
    or a.type_id = 1612 as ueberholt
from player_absences a
left join sideline_types t on t.id = a.type_id
left join letzter_einsatz e on e.player_id = a.player_id

union all

select
  -1000000000 - (v.season * 100 + v.round) as id,
  v.player_id,
  'injury'::text as kategorie,
  null::int as type_id,
  f.kickoff::date as seit,
  null::date as bis,
  null::int as spiele_verpasst,
  v.erkannt_am as updated_at,
  'Substituted Off Injured'::text as grund_quelle,
  e.gespielt_am,
  'ausgewechselt'::text as quelle,
  v.round as runde,
  v.minute,
  false as ueberholt
from verletzt_ausgewechselt v
join fixtures f on f.id = v.fixture_id
left join letzter_einsatz e on e.player_id = v.player_id
where not exists (
        -- Ein ausgeblendeter Eintrag darf die Beobachtung nicht verdecken:
        -- Wer nur „No Eligibility" traegt, gilt hier als ungemeldet.
        select 1 from player_absences a
         where a.player_id = v.player_id and a.type_id is distinct from 1612)
  -- Er hat seither gespielt.
  and coalesce(e.letzte_runde, 0) <= v.round
  -- Oder der Verein plant ihn wieder ein: Elf **oder** Bank eines spaeteren
  -- Spiels. Auf die Bank setzt niemand einen Verletzten.
  and not exists (
        select 1
          from predicted_lineups pl
          join fixtures f2 on f2.id = pl.fixture_id
         where pl.player_id = v.player_id
           and f2.kickoff > f.kickoff);

grant select on public.player_absences_v to anon, authenticated;
