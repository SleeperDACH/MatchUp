-- 0133: Kartensperren aus anderen Wettbewerben ausblenden.
--
-- Gemeldet am 14.10.2026: „Warum wird bei Olise eine Gelbsperre angezeigt? Er
-- ist in der Champions League vom Platz geflogen, das wird aber nicht in der
-- Bundesliga gewertet."
--
-- Sportmonks führt Sperren je Verein, **ohne** Wettbewerb: `season_id` ist bei
-- allen Kartensperren `null` (nachgesehen für Olise, Bernardo, Suzuki,
-- Bensebaini). Eine Gelb-Rote Karte in der Champions League landet damit als
-- „Indirect Card Suspension" genauso in der Liste wie eine aus der Bundesliga
-- — und die App zeigte Olise als gesperrt, obwohl er am Samstag spielen darf.
--
-- **Gegenprobe aus den eigenen Daten**, dieselbe Bauart wie bei
-- „No Eligibility" (0123): Eine Kartensperre zählt nur, wenn der Spieler die
-- passende Karte in den zehn Tagen davor in einem **Bundesliga**-Spiel
-- gesehen hat. `player_match_stats` kennt nur Bundesliga-Spiele, genau das
-- macht sie zur richtigen Quelle. Nachgemessen am 14.10.2026:
--
--   Bernardo   Gelb-Rot  ab 11.10.  Gelb-Rot am 5. Spieltag (10.10.)  bleibt
--   Suzuki     Gelb-Rot  ab 12.10.  Gelb-Rot am 5. Spieltag (11.10.)  bleibt
--   Olise      Gelb-Rot  ab 14.10.  keine Karte in der Bundesliga     fällt
--   Bensebaini Rot       ab 23.08.  keine Karte, hat seither gespielt fällt
--
-- Welche Karte zu welcher Sperre gehört, ist bei Sportmonks nachgesehen
-- (`/v3/core/types/<id>`): 1608 Rot, 1610 „Indirect Card" = **Gelb-Rot**,
-- 1611 Gelb (fünfte Karte). Sperren durch das Sportgericht (1615) bleiben
-- unberührt — die haben keine Karte, an der man sie prüfen könnte.
--
-- Nebenbei: 0132 übersetzte 1610 mit „Gelbsperre". Das ist 1611; 1610 ist
-- die Sperre nach Gelb-Rot.

update public.sideline_types set name_de = 'Gelb-Rot-Sperre' where id = 1610;

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
), karte as (
  -- Karten aus **Bundesliga**-Spielen — `player_match_stats` kennt nur die.
  select s.player_id, f.kickoff::date as tag, s.yellow, s.second_yellow, s.red
    from player_match_stats s
    join players p on p.id = s.player_id
    join fixtures f
      on f.season = s.season
     and f.round = s.round
     and f.league_id = 'bundesliga'
     and (fantasy_verein_kanonisch(f.home_name) = fantasy_verein_kanonisch(p.club)
       or fantasy_verein_kanonisch(f.away_name) = fantasy_verein_kanonisch(p.club))
   where s.yellow + s.second_yellow + s.red > 0
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
  coalesce(t.name_de,
           case when a.kategorie = 'suspended' then 'Sperre' else 'Verletzung' end)
    as grund_quelle,
  e.gespielt_am,
  'gemeldet'::text as quelle,
  null::int as runde,
  null::int as minute,
  -- „Gilt fuer die Bundesliga nicht (mehr)": vier Gruende, vier Zeilen.
  (e.gespielt_am is not null and a.seit is not null and e.gespielt_am::date > a.seit)
    or (a.kategorie = 'suspended' and a.seit is not null
        and a.seit < (select tag from saisonstart))
    or a.type_id = 1612
    -- Kartensperre ohne Bundesliga-Karte: gilt für einen anderen Wettbewerb.
    or (a.type_id in (1608, 1610, 1611)
        and a.seit is not null
        and not exists (
          select 1 from karte k
           where k.player_id = a.player_id
             and k.tag between a.seit - 10 and a.seit + 1
             and case a.type_id
                   when 1608 then k.red > 0
                   when 1610 then k.second_yellow > 0 or k.red > 0
                   else k.yellow > 0
                 end)) as ueberholt
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
