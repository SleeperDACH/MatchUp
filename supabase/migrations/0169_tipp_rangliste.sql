-- 0169: Rangliste einer Tipprunde auf dem Server (18.11.2026, auf Ansage:
-- „Tabelle des Globalen Tippspiels auf dem Server berechnen").
--
-- Bisher lud jede App alle Tipps aller Mitglieder und rechnete selbst. Beim
-- Globalen Tippspiel mit Tausenden Mitgliedern wären das Hunderttausende
-- Zeilen je Aufruf. Diese Funktion liefert nur den **Ausschnitt**, den die
-- Tabelle zeigt: die ersten `p_oben` Plätze und `p_umfeld` Plätze über und
-- unter dem Aufrufer, dazu für jeden den Platz vor `p_vor` (Bewegungspfeile)
-- und die Mitgliederzahl.
--
-- Gewertet werden beendete Spiele mit exakt / Tordifferenz / Tendenz /
-- falsch aus `scoring` — genau die Wertung des Globalen Tippspiels (4/3/2).
-- Quoten- und Alleinstellungs-Bonus rechnet diese Funktion **nicht**; Runden
-- mit Bonus bleiben bei der Rechnung in der App.
--
-- Platz nach Wettkampf-Art (1, 2, 2, 4), bei Gleichstand alphabetisch
-- sortiert — wie `ranksByPoints` in der App.
-- Rollback: drop function public.tipp_rangliste(uuid, int, int, timestamptz);

create or replace function public.tipp_rangliste(
  p_round  uuid,
  p_oben   int default 10,
  p_umfeld int default 2,
  p_vor    timestamptz default null
)
returns table (
  user_id      uuid,
  punkte       int,
  platz        int,
  platz_vorher int,
  mitglieder   int
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_scoring jsonb;
  v_ich     uuid := auth.uid();
begin
  select r.scoring into v_scoring from tip_rounds r where r.id = p_round;
  if v_scoring is null then
    return;
  end if;
  -- Nur Mitglieder sehen die Rangliste (wie die Tipps selbst).
  if not exists (select 1 from tip_round_members m
                  where m.round_id = p_round and m.user_id = v_ich) then
    return;
  end if;

  return query
  with wertung as (
    select t.user_id,
           f.kickoff,
           case
             when t.home_goals = f.home_score and t.away_goals = f.away_score
               then coalesce((v_scoring->>'exact')::int, 0)
             when t.home_goals - t.away_goals = f.home_score - f.away_score
               then coalesce((v_scoring->>'goalDiff')::int, 0)
             when sign(t.home_goals - t.away_goals) = sign(f.home_score - f.away_score)
               then coalesce((v_scoring->>'tendency')::int, 0)
             else coalesce((v_scoring->>'wrongTip')::int, 0)
           end as p
      from tips t
      join fixtures f on f.id = t.fixture_id
     where t.round_id = p_round
       and f.status = 'finished'
       and f.home_score is not null
  ),
  summen as (
    select m.user_id,
           coalesce(sum(w.p), 0)::int as jetzt,
           coalesce(sum(w.p) filter (where p_vor is not null and w.kickoff < p_vor), 0)::int as vorher
      from tip_round_members m
      left join wertung w on w.user_id = m.user_id
     where m.round_id = p_round
     group by m.user_id
  ),
  geordnet as (
    select s.user_id, s.jetzt, s.vorher,
           rank() over (order by s.jetzt desc)::int as platz,
           rank() over (order by s.vorher desc)::int as platz_vorher,
           row_number() over (order by s.jetzt desc, lower(coalesce(p.username, '')), s.user_id) as nr,
           count(*) over ()::int as mitglieder
      from summen s
      left join profiles p on p.id = s.user_id
  ),
  meine as (
    select g.nr from geordnet g where g.user_id = v_ich
  )
  select g.user_id, g.jetzt, g.platz, g.platz_vorher, g.mitglieder
    from geordnet g
   where g.nr <= p_oben
      or exists (select 1 from meine x where abs(g.nr - x.nr) <= p_umfeld)
   order by g.nr;
end
$function$;

grant execute on function public.tipp_rangliste(uuid, int, int, timestamptz) to authenticated;

-- Die Abfrage oben liest Tipps je Runde und Mitglieder je Runde. Beide
-- Tabellen haben die Runde vorn im Primärschlüssel; ein eigener Index ist
-- deshalb nicht nötig (geprüft: tips_pkey, tip_round_members_pkey).
