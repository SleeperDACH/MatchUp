-- Der Ersteller einer Tipprunde darf Tipps für Mitglieder nachtragen — auch
-- nach Anstoß (z. B. wenn jemand das Tippen vergessen hat). Die normale
-- Tipp-RLS erlaubt nur eigene Tipps vor Anstoß; dies umgeht das bewusst und
-- ist auf den Ersteller beschränkt (security definer).

create function public.tip_admin_set_tip(
  p_round_id uuid, p_user uuid, p_fixture_id text, p_home int, p_away int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from tip_rounds
                 where id = p_round_id and created_by = auth.uid()) then
    raise exception 'Nur der Ersteller darf Tipps nachtragen';
  end if;
  if not exists (select 1 from tip_round_members
                 where round_id = p_round_id and user_id = p_user) then
    raise exception 'Nutzer ist kein Mitglied dieser Tipprunde';
  end if;
  if not exists (select 1 from fixtures where id = p_fixture_id) then
    raise exception 'Spiel noch nicht gespiegelt — bitte den Spieltag kurz öffnen';
  end if;
  if p_home < 0 or p_home > 99 or p_away < 0 or p_away > 99 then
    raise exception 'Ungültiges Ergebnis';
  end if;

  insert into tips (round_id, user_id, fixture_id, home_goals, away_goals, updated_at)
  values (p_round_id, p_user, p_fixture_id, p_home, p_away, now())
  on conflict (round_id, user_id, fixture_id)
    do update set home_goals = excluded.home_goals,
                  away_goals = excluded.away_goals,
                  updated_at = now();
end$$;
