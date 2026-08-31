-- Die Ausfall-Sicht verglich Vereinsnamen wieder buchstabengenau.
--
-- Gemeldet: „Lukas Pinckert ist seit 34 Spielen rot gesperrt? Glaube nicht,
-- dass das stimmt." Stimmte auch nicht — er hat an Spieltag 1 volle 90 Minuten
-- gespielt. In `player_absences` steht eine Rotsperre vom 29.10.2025 ohne
-- Enddatum; Sportmonks hat sie nie geschlossen.
--
-- **Genau dafür gibt es `ueberholt`**: Die Sicht vergleicht den Beginn des
-- Ausfalls mit dem letzten Einsatz aus unseren eigenen Minuten und wirft
-- Meldungen weg, die unsere Daten widerlegen. Bei ihm griff das nicht — die
-- Sicht verband `player_match_stats` und `fixtures` ueber
-- `f.home_name = p.club`, also buchstabengenau. Sein Verein heisst im Kader
-- „SV 07 Elversberg" und im Sportmonks-Spielplan „Elversberg".
--
-- **Derselbe Fehler wie 0108**, nur an einer anderen Stelle: Dort riss der
-- Waiver-Antrag fuer sieben Vereine, hier faellt die Ausfall-Pruefung fuer
-- dieselben sieben aus. Beim Aufraeumen von 0108 hatte ich die Funktionen
-- durchgesehen, aber **die Sichten nicht** — nachgezaehlt sind es zwei.
--
-- Verglichen wird jetzt auch hier die kanonische Form.

create or replace view public.player_absences_v
with (security_invoker = true) as
  with letzter_einsatz as (
    select s.player_id, max(f.kickoff) as gespielt_am
      from player_match_stats s
      join players p on p.id = s.player_id
      join fixtures f
        on f.season = s.season and f.round = s.round
       and f.league_id = 'bundesliga'
       and (public.fantasy_verein_kanonisch(f.home_name)
              = public.fantasy_verein_kanonisch(p.club)
         or public.fantasy_verein_kanonisch(f.away_name)
              = public.fantasy_verein_kanonisch(p.club))
     where s.minutes > 0
     group by s.player_id
  )
  select a.id, a.player_id, a.kategorie, a.type_id, a.seit, a.bis,
         a.spiele_verpasst, a.updated_at,
         t.name as grund_quelle,
         e.gespielt_am,
         e.gespielt_am is not null
           and a.seit is not null
           and e.gespielt_am::date > a.seit as ueberholt
    from player_absences a
    left join sideline_types t on t.id = a.type_id
    left join letzter_einsatz e on e.player_id = a.player_id;

-- Dieselbe Naht im Widerspruchs-Monitor: Er verglich `t.verein = p.club` und
-- sah damit fuer dieselben sieben Vereine nichts. Eine Wache, die genau die
-- Faelle nicht sieht, die eine andere Wache schon einmal uebersehen hat, ist
-- keine.
create or replace view public.stats_widersprueche
with (security_invoker = true) as
  with tore_je_team as (
    select f.season, f.round,
           public.fantasy_verein_kanonisch(f.home_name) as verein,
           f.home_score as tore
      from fixtures f
     where f.league_id = 'bundesliga' and f.id like 'sportmonks:%'
       and f.status = 'finished'
    union all
    select f.season, f.round,
           public.fantasy_verein_kanonisch(f.away_name),
           f.away_score
      from fixtures f
     where f.league_id = 'bundesliga' and f.id like 'sportmonks:%'
       and f.status = 'finished'
  )
  select s.season, s.round, s.player_id, p.name, p.club,
         'mehr Tore als die Mannschaft' as widerspruch,
         s.goals as wert, t.tore as vergleich
    from player_match_stats s
    join players p on p.id = s.player_id
    join tore_je_team t
      on t.season = s.season and t.round = s.round
     and t.verein = public.fantasy_verein_kanonisch(p.club)
   where s.goals > t.tore;
