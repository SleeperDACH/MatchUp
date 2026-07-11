-- Draft-Queue robust gegen doppelte Spieler-IDs: sollte die Eingabeliste (etwa
-- durch einen Client-/Realtime-Race) denselben Spieler mehrfach enthalten, darf
-- das Speichern nicht am Primary Key (league_id, manager_id, player_id)
-- scheitern. `on conflict do nothing` behält den ersten Eintrag samt Rang.

create or replace function public.fantasy_set_queue(
  p_league_id uuid, p_player_ids text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  delete from fantasy_draft_queue
    where league_id = p_league_id and manager_id = auth.uid();
  insert into fantasy_draft_queue (league_id, manager_id, player_id, rank)
    select p_league_id, auth.uid(), t.pid, t.ord
    from unnest(p_player_ids) with ordinality as t(pid, ord)
    on conflict (league_id, manager_id, player_id) do nothing;
end$$;
