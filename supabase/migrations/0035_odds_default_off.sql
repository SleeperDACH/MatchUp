-- Quoten-Bonus standardmäßig AUS: nur aktiv, wenn in der Runde bewusst
-- gewählt (scoring.oddsBonus = true). Bislang war der Default (fehlender Key)
-- „an" — Altrunden ohne Key bekommen ab jetzt keinen Bonus mehr.
--
-- Einziger Unterschied zu 0034: coalesce(..., true) -> coalesce(..., false)
-- in der oddsBonus-Bedingung. Spiegelt tip.dart (ScoringRules.oddsBonus
-- Default = false).

create or replace view public.tip_round_standings as
with scored as (
  select
    t.round_id,
    t.user_id,
    t.fixture_id,
    r.scoring,
    (f.status = 'finished') as finished,
    (case
      when t.home_goals = f.home_score and t.away_goals = f.away_score
        then (r.scoring ->> 'exact')::int
      when t.home_goals - t.away_goals = f.home_score - f.away_score
        then (r.scoring ->> 'goalDiff')::int
      when sign(t.home_goals - t.away_goals) = sign(f.home_score - f.away_score)
        then (r.scoring ->> 'tendency')::int
      else 0
    end) as base,
    (case
      when coalesce((r.scoring ->> 'oddsBonus')::boolean, false) is not true then 0
      when fo.fixture_id is null then 0
      when sign(t.home_goals - t.away_goals) <> sign(f.home_score - f.away_score) then 0
      when (case when f.home_score > f.away_score then fo.home_win
                 when f.home_score < f.away_score then fo.away_win
                 else fo.draw end)
           >= coalesce((r.scoring ->> 'oddsOdds2')::numeric, 5.0)
        then coalesce((r.scoring ->> 'oddsPoints2')::int, 5)
      when (case when f.home_score > f.away_score then fo.home_win
                 when f.home_score < f.away_score then fo.away_win
                 else fo.draw end)
           >= coalesce((r.scoring ->> 'oddsOdds1')::numeric, 3.0)
        then coalesce((r.scoring ->> 'oddsPoints1')::int, 1)
      else 0
    end) as odds_bonus,
    (t.home_goals = f.home_score and t.away_goals = f.away_score) as is_exact
  from public.tips t
  join public.fixtures f   on f.id = t.fixture_id
  join public.tip_rounds r on r.id = t.round_id
  left join public.fixture_odds fo on fo.fixture_id = t.fixture_id
),
with_solo as (
  select
    s.*,
    (case
      when s.is_exact
        and coalesce((s.scoring ->> 'solo')::int, 0) > 0
        and count(*) filter (where s.is_exact)
              over (partition by s.round_id, s.fixture_id) = 1
        then coalesce((s.scoring ->> 'solo')::int, 0)
      else 0
    end) as solo_bonus
  from scored s
)
select
  ws.round_id,
  ws.user_id,
  p.username,
  count(*) filter (where ws.finished)                         as scored_tips,
  coalesce(sum(
    case when ws.finished
      then ws.base + ws.odds_bonus + ws.solo_bonus
      else 0
    end), 0)                                                  as points
from with_solo ws
join public.profiles p on p.id = ws.user_id
group by ws.round_id, ws.user_id, p.username;

alter view public.tip_round_standings set (security_invoker = on);
