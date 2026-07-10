-- Hartes Maximum von 18 Teilnehmern pro Fantasy-Liga — unabhängig vom
-- (optionalen) Liga-Limit max_teams. „Unbegrenzt" (max_teams null) bedeutet
-- damit effektiv 18.

create or replace function public.join_fantasy_league(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_league_id uuid;
  v_status    text;
  v_max       int;
  v_effective int;
  v_count     int;
begin
  select id, draft_status, max_teams into v_league_id, v_status, v_max
  from fantasy_leagues where invite_code = p_invite_code;
  if v_league_id is null then
    raise exception 'Ungültiger Einladungscode';
  end if;
  if v_status <> 'setup' then
    raise exception 'Der Draft dieser Liga hat bereits begonnen';
  end if;
  -- Bereits Mitglied? Dann einfach zurückgeben (idempotent, kein Limit-Fehler).
  if exists (select 1 from fantasy_league_members
             where league_id = v_league_id and user_id = auth.uid()) then
    return v_league_id;
  end if;
  -- Effektives Limit: das kleinere aus Liga-Limit (falls gesetzt) und 18.
  v_effective := least(coalesce(v_max, 18), 18);
  select count(*) into v_count
    from fantasy_league_members where league_id = v_league_id;
  if v_count >= v_effective then
    raise exception 'Die Liga ist voll (% Teilnehmer)', v_effective;
  end if;
  insert into fantasy_league_members (league_id, user_id)
  values (v_league_id, auth.uid())
  on conflict do nothing;
  return v_league_id;
end;
$$;
