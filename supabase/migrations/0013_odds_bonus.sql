-- Quoten-Bonus für mutige, richtige Tipps.
-- 1. Eingefrorene 1X2-Quote je Spiel (zum Anstoß, vom Sync-Job geschrieben).
-- 2. Erweiterung der Standings-View um den Bonus.
--
-- Wertungslogik identisch zu lib/features/tippspiel/logic/tip_scoring.dart
-- (oddsBonus) — bei Änderungen beide Stellen anpassen.

create table public.fixture_odds (
  fixture_id  text primary key references public.fixtures (id) on delete cascade,
  home_win    double precision not null,
  draw        double precision not null,
  away_win    double precision not null,
  bookmaker   text,
  captured_at timestamptz not null default now()
);

alter table public.fixture_odds enable row level security;

create policy "Eingefrorene Quoten sind öffentlich lesbar"
  on public.fixture_odds for select using (true);
-- Schreiben nur über service_role (Snapshot im Sync-Job), keine Policy.

-- Standings inklusive Quoten-Bonus. Die Basiswertung bleibt unverändert;
-- der Bonus kommt nur bei richtiger Tendenz (Sieger/Remis korrekt) und nur
-- mit eingefrorener Quote on top:
--   Quote des Ausgangs > 5.0             → +5
--   sonst Quote ≥ 2.0 über dem Favoriten → +1
--   (die beiden Stufen stapeln nicht)
create or replace view public.tip_round_standings as
select
  t.round_id,
  t.user_id,
  p.username,
  count(*) filter (where f.status = 'finished')          as scored_tips,
  coalesce(sum(
    case
      when f.status <> 'finished' then 0
      else
        -- Basispunkte (unverändert)
        (case
          when t.home_goals = f.home_score and t.away_goals = f.away_score
            then (r.scoring ->> 'exact')::int
          when t.home_goals - t.away_goals = f.home_score - f.away_score
            then (r.scoring ->> 'goalDiff')::int
          when sign(t.home_goals - t.away_goals) = sign(f.home_score - f.away_score)
            then (r.scoring ->> 'tendency')::int
          else 0
        end)
        -- Quoten-Bonus (nur bei richtiger Tendenz und vorhandener Quote)
        + (case
            when fo.fixture_id is null then 0
            when sign(t.home_goals - t.away_goals)
                 <> sign(f.home_score - f.away_score) then 0
            when (case when f.home_score > f.away_score then fo.home_win
                       when f.home_score < f.away_score then fo.away_win
                       else fo.draw end) > 5.0 then 5
            when (case when f.home_score > f.away_score then fo.home_win
                       when f.home_score < f.away_score then fo.away_win
                       else fo.draw end)
                 - least(fo.home_win, fo.draw, fo.away_win) >= 2.0 then 1
            else 0
          end)
    end), 0)                                             as points
from public.tips t
join public.fixtures f   on f.id = t.fixture_id
join public.tip_rounds r on r.id = t.round_id
join public.profiles p   on p.id = t.user_id
left join public.fixture_odds fo on fo.fixture_id = t.fixture_id
group by t.round_id, t.user_id, p.username;

alter view public.tip_round_standings set (security_invoker = on);
