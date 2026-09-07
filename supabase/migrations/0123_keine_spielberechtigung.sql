-- „No Eligibility" ist keine Bundesliga-Sperre.
--
-- Gefragt: „Warum sind Can und Lerma 5 Monate gesperrt?" Zu Recht -- die
-- Anzeige war falsch, und zwar auf unserer Seite.
--
-- In `player_absences` standen 17 Eintraege vom Typ 1612 („No Eligibility"),
-- alle mit Beginn kurz nach dem Transferschluss und Ende im Winterfenster.
-- Nachgezaehlt am 07.09.2026, gruppiert nach Zeitraum und Verein:
--
--   03.09. bis 28.01.  11 Spieler  Dortmund, Leipzig, Stuttgart
--   04.09. bis 29.01.   5 Spieler  Leverkusen, Hoffenheim
--   04.09. bis 18.12.   1 Spieler  Freiburg
--
-- **Das sind genau die sechs Vereine im Europapokal, und die drei Zeitraeume
-- sind die Meldefristen dreier Wettbewerbe.** Kein Verein ausserhalb Europas
-- traegt einen solchen Eintrag. Es geht also um die Kaderliste eines
-- europaeischen Wettbewerbs -- fuer die Bundesliga sind diese Spieler
-- spielberechtigt.
--
-- Der Gegenbeweis steht in unseren eigenen Zahlen: Vier von ihnen haben am
-- 1. Spieltag gespielt (Konstantelias 54 Minuten, Hofmann 25, Stergiou 16,
-- Boniface 5) und danach den Eintrag bekommen. Wer spielt, ist nicht gesperrt.
--
-- **Sportmonks sagt nicht, welcher Wettbewerb gemeint ist** (`season_id` ist
-- bei allen 17 `null`). Damit ist der Eintrag fuer diese App nicht
-- zuzuordnen -- und ein Zustand, den wir nicht zuordnen koennen, darf nicht
-- als „gesperrt" dastehen. Dieselbe Regel wie ueberall in diesem Projekt:
-- „Ich weiss es nicht" sieht anders aus als eine Auskunft.
--
-- Die Zeilen bleiben in der Tabelle stehen; die Sicht blendet sie aus. Faellt
-- die Entscheidung spaeter anders, kostet es eine Zeile.
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
  and coalesce(e.letzte_runde, 0) <= v.round;

grant select on public.player_absences_v to anon, authenticated;
