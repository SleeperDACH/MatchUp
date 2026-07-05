-- Draft-Queue + Abwesend-Autopick.
--
-- * Jeder Manager kann sich eine priorisierte Wunschliste (Queue) anlegen —
--   auch schon vor Draftbeginn. Ist er am Zug und ein Auto-Pick greift, wird
--   der oberste noch verfügbare, phasen-gültige Spieler aus der Queue gezogen
--   (sonst der erste freie Spieler als Rückfall).
-- * Wer nicht pickt (Timer läuft ab) ODER den Draft-Raum verlässt, wird auf
--   „Auto" gestellt: dann feuert der Auto-Pick bei jedem seiner Züge sofort
--   (ohne den vollen Timer abzuwarten) — so lange, bis er dem Draft-Raum
--   wieder beitritt (Client setzt das Flag beim Betreten zurück).

alter table public.fantasy_league_members
  add column if not exists auto_pick boolean not null default false;

create table public.fantasy_draft_queue (
  league_id  uuid not null references public.fantasy_leagues (id) on delete cascade,
  manager_id uuid not null references public.profiles (id) on delete cascade,
  player_id  text not null references public.players (id),
  rank       int  not null,
  primary key (league_id, manager_id, player_id)
);

create index fantasy_draft_queue_order_idx
  on public.fantasy_draft_queue (league_id, manager_id, rank);

alter table public.fantasy_draft_queue enable row level security;

create policy "Manager sieht seine eigene Queue"
  on public.fantasy_draft_queue for select
  using (manager_id = auth.uid());

alter publication supabase_realtime add table public.fantasy_draft_queue;

-- Ganze Queue ersetzen (Client schickt die geordnete Liste bei jeder Änderung).
create function public.fantasy_set_queue(p_league_id uuid, p_player_ids text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  delete from fantasy_draft_queue
    where league_id = p_league_id and manager_id = auth.uid();
  insert into fantasy_draft_queue (league_id, manager_id, player_id, rank)
    select p_league_id, auth.uid(), t.pid, t.ord
    from unnest(p_player_ids) with ordinality as t(pid, ord);
end$$;

-- Auto-Modus setzen: Client ruft false beim Betreten, true beim Verlassen.
create function public.fantasy_set_auto_pick(p_league_id uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  update fantasy_league_members set auto_pick = p_on
    where league_id = p_league_id and user_id = auth.uid();
end$$;

-- Vorrücken: zusätzlich den gedrafteten Spieler aus allen Queues der Liga
-- entfernen (0005-Version + Queue-Bereinigung).
create or replace function public.fantasy_advance(
  p_league_id uuid, p_manager uuid, p_player text, p_is_auto boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_p int; v_n int; v_squad int; v_total int; v_secs int;
  v_phase text; v_u20 int;
begin
  select picks_made, draft_pick_seconds, public.fantasy_squad_size(roster),
         draft_phase, u20_rounds
    into v_p, v_secs, v_squad, v_phase, v_u20
    from fantasy_leagues where id = p_league_id;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  v_total := v_n * (case when v_phase = 'u20' then v_u20 else v_squad end);

  insert into draft_picks (league_id, phase, pick_number, round, manager_id, player_id, is_auto)
  values (p_league_id, v_phase, v_p + 1, (v_p / v_n) + 1, p_manager, p_player, p_is_auto);

  delete from fantasy_draft_queue
    where league_id = p_league_id and player_id = p_player;

  if v_p + 1 >= v_total then
    update fantasy_leagues
      set picks_made = v_p + 1, current_pick_deadline = null, draft_status = 'done'
      where id = p_league_id;
  else
    update fantasy_leagues
      set picks_made = v_p + 1,
          current_pick_deadline = now() + (v_secs || ' seconds')::interval
      where id = p_league_id;
  end if;
end$$;

-- Auto-Pick: feuert bei abgelaufenem Timer ODER wenn der aktuelle Manager im
-- Auto-Modus (abwesend) ist. Wählt aus der Queue (sonst erster freier Spieler)
-- unter Beachtung des Phasen-Pools. Ein verpasster Pick (Timerablauf) stellt
-- den Manager selbst auf Auto.
create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int; v_away boolean; v_expired boolean;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season
    into v_status, v_deadline, v_mode, v_phase, v_season
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;

  if auth.uid() is not null and not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  v_manager := public.fantasy_current_manager(p_league_id);
  select coalesce(auto_pick, false) into v_away
    from fantasy_league_members
    where league_id = p_league_id and user_id = v_manager;

  v_expired := v_deadline is not null and now() > v_deadline;
  if not v_expired and not coalesce(v_away, false) then return false; end if;

  -- Queue zuerst.
  select q.player_id into v_player
    from fantasy_draft_queue q join players p on p.id = q.player_id
    where q.league_id = p_league_id and q.manager_id = v_manager
      and q.player_id not in
          (select player_id from fantasy_rosters where league_id = p_league_id)
      and (v_mode <> 'dynasty'
           or (v_phase = 'u20')
              = public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
    order by q.rank limit 1;

  -- Rückfall: erster freier, phasen-gültiger Spieler.
  if v_player is null then
    select p.id into v_player from players p
      where p.id not in
            (select player_id from fantasy_rosters where league_id = p_league_id)
        and (v_mode <> 'dynasty'
             or (v_phase = 'u20')
                = public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
      order by p.name limit 1;
  end if;

  if v_player is null then
    update fantasy_leagues
      set draft_status = 'done', current_pick_deadline = null
      where id = p_league_id;
    return false;
  end if;

  -- Verpasster Pick → Manager auf Auto, bis er wieder beitritt.
  if v_expired then
    update fantasy_league_members set auto_pick = true
      where league_id = p_league_id and user_id = v_manager;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, v_player, true);
  return true;
end$$;
