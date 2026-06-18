-- Wer hat in einer Tipprunde welches Spiel bereits getippt — nur die
-- Existenz (user_id + fixture_id), NICHT der Tipp selbst. Damit kann die
-- Tabelle vor Anstoß ein Schloss zeigen (Gegner hat getippt) bzw. eine leere
-- Zelle (noch nicht getippt), ohne fremde Tipps zu verraten.
--
-- security definer + Mitglieds-Check: nur Mitglieder der Runde erhalten Daten;
-- die Tipp-Werte (home_goals/away_goals) bleiben außen vor.
create function public.round_tip_presence(p_round_id uuid)
returns table (user_id uuid, fixture_id text)
language sql
stable
security definer
set search_path = public
as $$
  select t.user_id, t.fixture_id
  from tips t
  where t.round_id = p_round_id
    and public.is_round_member(p_round_id);
$$;
