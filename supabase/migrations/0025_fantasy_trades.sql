-- Trades zwischen Managern einer Fantasy-Liga.
--
-- Ein Manager bietet eigene Spieler an und fordert Spieler eines anderen
-- Managers. Nimmt der Empfänger an, werden die Kader **sofort** getauscht
-- (kein Commissioner-Schritt). Nur die beiden beteiligten Parteien sehen
-- ein Angebot. Die Trade-Deadline wird clientseitig geprüft (Playoff-Logik
-- liegt dort); der Server prüft Besitz, Mitgliedschaft und Status.

-- Kadereinträge dürfen künftig auch per Trade entstehen.
alter table public.fantasy_rosters
  drop constraint if exists fantasy_rosters_acquired_via_check;
alter table public.fantasy_rosters
  add constraint fantasy_rosters_acquired_via_check
  check (acquired_via in ('draft', 'fa', 'waiver', 'trade'));

create table public.fantasy_trades (
  id           uuid primary key default gen_random_uuid(),
  league_id    uuid not null references public.fantasy_leagues (id) on delete cascade,
  from_manager uuid not null references public.profiles (id) on delete cascade,
  to_manager   uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending'
               check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  message      text check (message is null or char_length(message) <= 500),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  check (from_manager <> to_manager)
);

create index fantasy_trades_league_idx on public.fantasy_trades (league_id, status);
create index fantasy_trades_to_idx on public.fantasy_trades (to_manager, status);
create index fantasy_trades_from_idx on public.fantasy_trades (from_manager, status);

-- Ein Spieler im Angebot: [giver] gibt [player_id] ab (an die jeweils andere
-- Seite des Trades).
create table public.fantasy_trade_items (
  trade_id  uuid not null references public.fantasy_trades (id) on delete cascade,
  giver     uuid not null references public.profiles (id) on delete cascade,
  player_id text not null references public.players (id),
  primary key (trade_id, player_id)
);

alter table public.fantasy_trades enable row level security;
alter table public.fantasy_trade_items enable row level security;

-- Nur die beiden beteiligten Manager sehen ein Angebot.
create policy "Beteiligte sehen ihre Trades"
  on public.fantasy_trades for select
  using (from_manager = auth.uid() or to_manager = auth.uid());

create policy "Beteiligte sehen die Trade-Positionen"
  on public.fantasy_trade_items for select
  using (exists (
    select 1 from public.fantasy_trades t
    where t.id = trade_id
      and (t.from_manager = auth.uid() or t.to_manager = auth.uid())));

-- Live: eingehende Angebote und Statuswechsel erscheinen sofort.
alter publication supabase_realtime add table public.fantasy_trades;

-- ---------------------------------------------------------------------
-- Angebot erstellen: eigene Spieler (p_offer) gegen fremde (p_request).
-- ---------------------------------------------------------------------
create function public.fantasy_propose_trade(
  p_league_id uuid, p_to_manager uuid,
  p_offer_players text[], p_request_players text[], p_message text)
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
                 where league_id = p_league_id and user_id = p_to_manager) then
    raise exception 'Der Empfänger ist kein Mitglied dieser Liga';
  end if;
  if coalesce(array_length(p_offer_players, 1), 0) = 0
     and coalesce(array_length(p_request_players, 1), 0) = 0 then
    raise exception 'Ein Angebot braucht mindestens einen Spieler';
  end if;

  -- Besitz prüfen: Angebotene gehören mir, geforderte dem Empfänger.
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
    values (p_league_id, v_uid, p_to_manager, nullif(btrim(coalesce(p_message, '')), ''))
    returning id into v_trade_id;

  foreach v_pid in array coalesce(p_offer_players, '{}') loop
    insert into fantasy_trade_items (trade_id, giver, player_id)
      values (v_trade_id, v_uid, v_pid);
  end loop;
  foreach v_pid in array coalesce(p_request_players, '{}') loop
    insert into fantasy_trade_items (trade_id, giver, player_id)
      values (v_trade_id, p_to_manager, v_pid);
  end loop;

  return v_trade_id;
end$$;

-- ---------------------------------------------------------------------
-- Auf ein Angebot reagieren: annehmen (sofortiger Tausch) oder ablehnen.
-- ---------------------------------------------------------------------
create function public.fantasy_respond_trade(p_trade_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trade fantasy_trades;
  v_item fantasy_trade_items;
  v_other uuid;
begin
  select * into v_trade from fantasy_trades where id = p_trade_id for update;
  if v_trade.id is null then raise exception 'Angebot nicht gefunden'; end if;
  if v_trade.to_manager <> v_uid then
    raise exception 'Nur der Empfänger kann auf das Angebot reagieren';
  end if;
  if v_trade.status <> 'pending' then
    raise exception 'Das Angebot ist nicht mehr offen';
  end if;

  if not p_accept then
    update fantasy_trades set status = 'rejected', resolved_at = now()
      where id = p_trade_id;
    return;
  end if;

  -- Annehmen: Besitz jedes Spielers erneut prüfen, dann tauschen.
  for v_item in select * from fantasy_trade_items where trade_id = p_trade_id loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = v_trade.league_id
                     and manager_id = v_item.giver and player_id = v_item.player_id) then
      raise exception 'Spieler nicht mehr verfügbar — Angebot hinfällig';
    end if;
  end loop;

  for v_item in select * from fantasy_trade_items where trade_id = p_trade_id loop
    -- Empfänger jedes Spielers ist die jeweils andere Partei.
    v_other := case when v_item.giver = v_trade.from_manager
                    then v_trade.to_manager else v_trade.from_manager end;
    update fantasy_rosters
      set manager_id = v_other, acquired_via = 'trade', acquired_at = now()
      where league_id = v_trade.league_id and player_id = v_item.player_id;
  end loop;

  update fantasy_trades set status = 'accepted', resolved_at = now()
    where id = p_trade_id;
end$$;

-- ---------------------------------------------------------------------
-- Eigenes Angebot zurückziehen (nur der Absender, solange offen).
-- ---------------------------------------------------------------------
create function public.fantasy_cancel_trade(p_trade_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_from uuid; v_status text;
begin
  select from_manager, status into v_from, v_status
    from fantasy_trades where id = p_trade_id for update;
  if v_from is null then raise exception 'Angebot nicht gefunden'; end if;
  if v_from <> v_uid then raise exception 'Nur der Absender kann zurückziehen'; end if;
  if v_status <> 'pending' then raise exception 'Das Angebot ist nicht mehr offen'; end if;
  update fantasy_trades set status = 'cancelled', resolved_at = now()
    where id = p_trade_id;
end$$;
