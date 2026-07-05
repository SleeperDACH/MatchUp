-- Gegenangebot schließt das Original: neuer Trade-Status 'countered'
-- (gekontert). Sendet der Empfänger ein Gegenangebot, wird das ursprüngliche
-- (offene) Angebot auf 'countered' gesetzt.

alter table public.fantasy_trades
  drop constraint if exists fantasy_trades_status_check;
alter table public.fantasy_trades
  add constraint fantasy_trades_status_check
  check (status in ('pending', 'accepted', 'rejected', 'cancelled', 'countered'));

-- propose_trade um p_counter_of erweitern (schließt das gekonterte Original).
drop function if exists public.fantasy_propose_trade(uuid, uuid, text[], text[], text);

create function public.fantasy_propose_trade(
  p_league_id uuid, p_to_manager uuid,
  p_offer_players text[], p_request_players text[], p_message text,
  p_counter_of uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trade_id uuid;
  v_pid text;
begin
  if v_uid is null then raise exception 'Nicht angemeldet'; end if;
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  if v_uid = p_to_manager then raise exception 'Kein Trade mit dir selbst'; end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = p_to_manager
                   and not vacant) then
    raise exception 'Der Empfänger ist kein Mitglied dieser Liga';
  end if;
  if coalesce(array_length(p_offer_players, 1), 0) = 0
     and coalesce(array_length(p_request_players, 1), 0) = 0 then
    raise exception 'Ein Angebot braucht mindestens einen Spieler';
  end if;

  foreach v_pid in array coalesce(p_offer_players, '{}') loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and manager_id = v_uid
                     and player_id = v_pid) then
      raise exception 'Angebotener Spieler nicht in deinem Kader';
    end if;
  end loop;
  foreach v_pid in array coalesce(p_request_players, '{}') loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and manager_id = p_to_manager
                     and player_id = v_pid) then
      raise exception 'Geforderter Spieler nicht im Kader des Empfängers';
    end if;
  end loop;

  insert into fantasy_trades (league_id, from_manager, to_manager, message)
    values (p_league_id, v_uid, p_to_manager,
            nullif(btrim(coalesce(p_message, '')), ''))
    returning id into v_trade_id;

  foreach v_pid in array coalesce(p_offer_players, '{}') loop
    insert into fantasy_trade_items (trade_id, giver, player_id)
      values (v_trade_id, v_uid, v_pid);
  end loop;
  foreach v_pid in array coalesce(p_request_players, '{}') loop
    insert into fantasy_trade_items (trade_id, giver, player_id)
      values (v_trade_id, p_to_manager, v_pid);
  end loop;

  -- Gegenangebot: das ursprüngliche (offene) Angebot schließen. Nur der
  -- Empfänger des Originals (= jetziger Absender) darf es kontern.
  if p_counter_of is not null then
    update fantasy_trades set status = 'countered', resolved_at = now()
      where id = p_counter_of and to_manager = v_uid and status = 'pending';
  end if;

  return v_trade_id;
end$$;
