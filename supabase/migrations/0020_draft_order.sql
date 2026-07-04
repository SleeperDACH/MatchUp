-- Draft-Reihenfolge: automatisch (zufällig beim Start) oder manuell
-- (der Ersteller platziert die Teilnehmer vorab).

alter table public.fantasy_leagues
  add column if not exists draft_order_mode text not null default 'auto'
    check (draft_order_mode in ('auto', 'manual'));

-- ---------------------------------------------------------------------
-- Reihenfolge manuell setzen (Ersteller, nur im Setup). Die Positionen
-- ergeben sich aus der Array-Reihenfolge; setzt zugleich den Modus auf
-- 'manual'.
-- ---------------------------------------------------------------------
create or replace function public.set_fantasy_draft_order(
  p_league_id uuid, p_user_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_count int;
begin
  select created_by, draft_status into v_created_by, v_status
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann die Reihenfolge festlegen';
  end if;
  if v_status <> 'setup' then
    raise exception 'Der Draft wurde bereits gestartet';
  end if;

  select count(*) into v_count
    from fantasy_league_members where league_id = p_league_id;
  if coalesce(array_length(p_user_ids, 1), 0) <> v_count then
    raise exception 'Die Reihenfolge muss alle Teilnehmer enthalten';
  end if;
  if exists (
      select 1 from unnest(p_user_ids) uid
      where uid not in (select user_id from fantasy_league_members
                        where league_id = p_league_id)) then
    raise exception 'Ungültige Teilnehmerliste';
  end if;

  update fantasy_league_members m
    set draft_position = arr.pos
    from (select uid, ord as pos
            from unnest(p_user_ids) with ordinality as t(uid, ord)) arr
    where m.league_id = p_league_id and m.user_id = arr.uid;

  update fantasy_leagues
    set draft_order_mode = 'manual' where id = p_league_id;
end$$;

-- ---------------------------------------------------------------------
-- Draft-Start: bei 'manual' die vorab gesetzten Positionen nutzen, sonst
-- (auto) zufällig auslosen. (ansonsten wie 0005)
-- ---------------------------------------------------------------------
create or replace function public.start_fantasy_draft(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_n int; v_secs int; v_mode text;
begin
  select created_by, draft_status, draft_pick_seconds, draft_order_mode
    into v_created_by, v_status, v_secs, v_mode
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den Draft starten';
  end if;
  if v_status <> 'setup' then raise exception 'Der Draft wurde bereits gestartet'; end if;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  if v_n < 1 then raise exception 'Mindestens ein Manager nötig'; end if;

  if v_mode = 'manual' then
    if exists (select 1 from fantasy_league_members
               where league_id = p_league_id and draft_position is null) then
      raise exception 'Bitte zuerst die Draft-Reihenfolge festlegen';
    end if;
  else
    with shuffled as (
      select user_id, row_number() over (order by random()) as pos
      from fantasy_league_members where league_id = p_league_id
    )
    update fantasy_league_members m
      set draft_position = s.pos
      from shuffled s
      where m.league_id = p_league_id and m.user_id = s.user_id;
  end if;

  update fantasy_leagues
    set draft_status = 'drafting', draft_phase = 'startup',
        picks_made = 0, draft_started_at = now(),
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;
