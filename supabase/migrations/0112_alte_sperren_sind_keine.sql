-- Eine Rotsperre aus der Vorsaison ist keine Sperre mehr.
--
-- Nach der Namens-Korrektur (0111) blieb ein zweiter Fall stehen: Felix Goetze,
-- „Red Card Suspension" seit dem 30.10.2025, 32 verpasste Spiele. Eine
-- Rotsperre laeuft ueber ein bis drei Spiele, in Ausnahmen ueber eine Handvoll
-- — **nie ueber zehn Monate und einen Saisonwechsel**. Die Meldung ist ein
-- Rest, den Sportmonks nie geschlossen hat.
--
-- Die vorhandene Pruefung (`ueberholt`) vergleicht mit unseren eigenen
-- Minuten und kann ihn nicht widerlegen: Er hat in dieser Saison **gar nicht**
-- gespielt. Deshalb eine zweite, unabhaengige Regel — aber nur fuer Sperren:
--
-- **Verletzungen bleiben unangetastet.** Ein Kreuzbandriss vom Oktober laeuft
-- im August durchaus noch; zwoelf der aktuellen Meldungen sind genau das. Sie
-- pauschal zu verwerfen hiesse, richtige Auskuenfte gegen falsche zu tauschen.
--
-- Der Saisonstart wird nicht hartkodiert, sondern aus dem Spielplan genommen:
-- der frueheste Anpfiff der juengsten Bundesliga-Saison, die wir haben.

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
  ),
  saisonstart as (
    select min(f.kickoff)::date as tag
      from fixtures f
     where f.league_id = 'bundesliga'
       and f.season = (select max(season) from fixtures
                        where league_id = 'bundesliga')
  )
  select a.id, a.player_id, a.kategorie, a.type_id, a.seit, a.bis,
         a.spiele_verpasst, a.updated_at,
         t.name as grund_quelle,
         e.gespielt_am,
         (
           -- Er hat nach Beginn des Ausfalls gespielt.
           (e.gespielt_am is not null and a.seit is not null
              and e.gespielt_am::date > a.seit)
           -- …oder es ist eine Sperre aus einer frueheren Saison.
           or (a.kategorie = 'suspended' and a.seit is not null
                 and a.seit < (select tag from saisonstart))
         ) as ueberholt
    from player_absences a
    left join sideline_types t on t.id = a.type_id
    left join letzter_einsatz e on e.player_id = a.player_id;
