-- Öffentliches Ligasystem: Sichtbarkeit (privat/öffentlich) + Beitrittsmodus
-- (freier Eintritt / auf Einladung) für Fantasy-Ligen UND Tipprunden, plus
-- Beitrittsanfragen (öffentlich–auf Einladung) mit Admin-Bestätigung und eine
-- Suche über öffentliche Wettbewerbe.
--
-- Sicherheit: Die Basistabellen bleiben mitgliederseitig lesbar. Alle
-- Nicht-Mitglieder-Zugriffe (Suche, Direktbeitritt, Anfrage) laufen über
-- security-definer-RPCs, die nur unbedenkliche Felder zurückgeben —
-- invite_code und Scoring werden dabei nie geleakt.

-- 1) Sichtbarkeits-Spalten (Bestandsdaten bleiben privat/frei) --------------
alter table public.fantasy_leagues
  add column if not exists visibility  text not null default 'private'
    check (visibility in ('private', 'public')),
  add column if not exists join_policy text not null default 'open'
    check (join_policy in ('open', 'invite'));

alter table public.tip_rounds
  add column if not exists visibility  text not null default 'private'
    check (visibility in ('private', 'public')),
  add column if not exists join_policy text not null default 'open'
    check (join_policy in ('open', 'invite'));

-- 2) Beitrittsanfragen (nur „öffentlich – auf Einladung") -------------------
-- Eine Zeile = eine offene Anfrage. Annehmen → Mitglied + Zeile löschen,
-- Ablehnen → Zeile löschen (kein Verlauf; erneute Anfrage möglich).
create table public.fantasy_join_requests (
  league_id  uuid not null references public.fantasy_leagues (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
alter table public.fantasy_join_requests enable row level security;

create policy "Requester oder Admin liest Anfragen"
  on public.fantasy_join_requests for select
  using (user_id = auth.uid() or public.fantasy_is_admin(league_id));
create policy "Nur selbst anfragen"
  on public.fantasy_join_requests for insert
  with check (user_id = auth.uid());
create policy "Requester oder Admin entfernt Anfrage"
  on public.fantasy_join_requests for delete
  using (user_id = auth.uid() or public.fantasy_is_admin(league_id));

create table public.tip_join_requests (
  round_id   uuid not null references public.tip_rounds (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (round_id, user_id)
);
alter table public.tip_join_requests enable row level security;

create policy "Requester oder Admin liest Tip-Anfragen"
  on public.tip_join_requests for select
  using (user_id = auth.uid()
         or exists (select 1 from tip_rounds r
                    where r.id = round_id and r.created_by = auth.uid()));
create policy "Nur selbst Tip-Anfrage"
  on public.tip_join_requests for insert
  with check (user_id = auth.uid());
create policy "Requester oder Admin entfernt Tip-Anfrage"
  on public.tip_join_requests for delete
  using (user_id = auth.uid()
         or exists (select 1 from tip_rounds r
                    where r.id = round_id and r.created_by = auth.uid()));

-- Live: neue Anfragen erscheinen beim Admin sofort (RLS-UPDATE/DELETE brauchen
-- die vollständige alte Zeile, siehe 0057_friends).
alter table public.fantasy_join_requests replica identity full;
alter table public.tip_join_requests replica identity full;
alter publication supabase_realtime add table public.fantasy_join_requests;
alter publication supabase_realtime add table public.tip_join_requests;

-- 3) Suche über öffentliche Wettbewerbe ------------------------------------
-- Liefert nur unbedenkliche Felder plus den Status des Aufrufers (Mitglied?
-- bereits angefragt?). Fantasy nur vor Draft-Start (danach nicht beitretbar).
create function public.search_public_leagues(p_query text)
returns table (
  kind         text,
  id           uuid,
  name         text,
  logo_url     text,
  logo_emoji   text,
  logo_color   text,
  season       int,
  member_count int,
  max_teams    int,
  join_policy  text,
  joinable     boolean,
  is_member    boolean,
  requested    boolean
)
language sql stable security definer set search_path = public as $$
  select 'fantasy'::text, l.id, l.name, l.logo_url, l.logo_emoji, l.logo_color,
         l.season,
         (select count(*)::int from fantasy_league_members m
            where m.league_id = l.id and not m.vacant),
         least(coalesce(l.max_teams, 18), 18),
         l.join_policy,
         (l.join_policy = 'open'),
         exists (select 1 from fantasy_league_members m
                   where m.league_id = l.id and m.user_id = auth.uid()),
         exists (select 1 from fantasy_join_requests q
                   where q.league_id = l.id and q.user_id = auth.uid())
    from fantasy_leagues l
   where l.visibility = 'public'
     and l.draft_status = 'setup'
     and (coalesce(p_query, '') = '' or l.name ilike '%' || p_query || '%')
  union all
  select 'tip'::text, r.id, r.name, r.logo_url, r.logo_emoji, r.logo_color,
         r.season,
         (select count(*)::int from tip_round_members m where m.round_id = r.id),
         null::int,
         r.join_policy,
         (r.join_policy = 'open'),
         exists (select 1 from tip_round_members m
                   where m.round_id = r.id and m.user_id = auth.uid()),
         exists (select 1 from tip_join_requests q
                   where q.round_id = r.id and q.user_id = auth.uid())
    from tip_rounds r
   where r.visibility = 'public'
     and (coalesce(p_query, '') = '' or r.name ilike '%' || p_query || '%')
  order by 8 desc, 3;
$$;

-- 4) Direktbeitritt (freier Eintritt) --------------------------------------
-- Fantasy: spiegelt die Logik von join_fantasy_league (setup → reguläres Team
-- mit 18er-Limit, danach → pending).
create function public.join_public_fantasy_league(p_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_vis text; v_pol text; v_max int; v_eff int; v_count int;
begin
  select draft_status, visibility, join_policy, max_teams
    into v_status, v_vis, v_pol, v_max
    from fantasy_leagues where id = p_id;
  if v_status is null then raise exception 'Liga nicht gefunden'; end if;
  if v_vis <> 'public' or v_pol <> 'open' then
    raise exception 'Diese Liga ist nicht frei beitretbar';
  end if;
  if exists (select 1 from fantasy_league_members
             where league_id = p_id and user_id = auth.uid()) then
    return p_id;
  end if;
  if v_status = 'setup' then
    v_eff := least(coalesce(v_max, 18), 18);
    select count(*) into v_count
      from fantasy_league_members where league_id = p_id;
    if v_count >= v_eff then
      raise exception 'Die Liga ist voll (% Teilnehmer)', v_eff;
    end if;
    insert into fantasy_league_members (league_id, user_id)
    values (p_id, auth.uid()) on conflict do nothing;
  else
    insert into fantasy_league_members (league_id, user_id, pending)
    values (p_id, auth.uid(), true) on conflict do nothing;
  end if;
  return p_id;
end$$;

create function public.join_public_tip_round(p_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_vis text; v_pol text;
begin
  select visibility, join_policy into v_vis, v_pol
    from tip_rounds where id = p_id;
  if v_vis is null then raise exception 'Runde nicht gefunden'; end if;
  if v_vis <> 'public' or v_pol <> 'open' then
    raise exception 'Diese Runde ist nicht frei beitretbar';
  end if;
  insert into tip_round_members (round_id, user_id)
  values (p_id, auth.uid()) on conflict do nothing;
  return p_id;
end$$;

-- 5) Beitrittsanfrage (auf Einladung) --------------------------------------
create function public.request_join_fantasy_league(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_vis text; v_pol text;
begin
  select visibility, join_policy into v_vis, v_pol
    from fantasy_leagues where id = p_id;
  if v_vis is null then raise exception 'Liga nicht gefunden'; end if;
  if v_vis <> 'public' or v_pol <> 'invite' then
    raise exception 'Für diese Liga ist keine Anfrage möglich';
  end if;
  if exists (select 1 from fantasy_league_members
             where league_id = p_id and user_id = auth.uid()) then
    raise exception 'Du bist bereits Mitglied';
  end if;
  insert into fantasy_join_requests (league_id, user_id)
  values (p_id, auth.uid()) on conflict do nothing;
end$$;

create function public.request_join_tip_round(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_vis text; v_pol text;
begin
  select visibility, join_policy into v_vis, v_pol
    from tip_rounds where id = p_id;
  if v_vis is null then raise exception 'Runde nicht gefunden'; end if;
  if v_vis <> 'public' or v_pol <> 'invite' then
    raise exception 'Für diese Runde ist keine Anfrage möglich';
  end if;
  if exists (select 1 from tip_round_members
             where round_id = p_id and user_id = auth.uid()) then
    raise exception 'Du bist bereits Mitglied';
  end if;
  insert into tip_join_requests (round_id, user_id)
  values (p_id, auth.uid()) on conflict do nothing;
end$$;

-- 6) Anfrage bearbeiten (nur Admin) ----------------------------------------
create function public.respond_fantasy_join_request(
  p_league uuid, p_user uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v_status text; v_max int; v_eff int; v_count int;
begin
  if not public.fantasy_is_admin(p_league) then
    raise exception 'Nur der Admin kann Anfragen bearbeiten';
  end if;
  if not exists (select 1 from fantasy_join_requests
                 where league_id = p_league and user_id = p_user) then
    raise exception 'Anfrage nicht gefunden';
  end if;
  if p_accept and not exists (select 1 from fantasy_league_members
                              where league_id = p_league and user_id = p_user) then
    select draft_status, max_teams into v_status, v_max
      from fantasy_leagues where id = p_league;
    if v_status = 'setup' then
      v_eff := least(coalesce(v_max, 18), 18);
      select count(*) into v_count
        from fantasy_league_members where league_id = p_league;
      if v_count >= v_eff then
        raise exception 'Die Liga ist voll (% Teilnehmer)', v_eff;
      end if;
      insert into fantasy_league_members (league_id, user_id)
      values (p_league, p_user) on conflict do nothing;
    else
      insert into fantasy_league_members (league_id, user_id, pending)
      values (p_league, p_user, true) on conflict do nothing;
    end if;
  end if;
  delete from fantasy_join_requests where league_id = p_league and user_id = p_user;
end$$;

create function public.respond_tip_join_request(
  p_round uuid, p_user uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from tip_rounds
                 where id = p_round and created_by = auth.uid()) then
    raise exception 'Nur der Admin kann Anfragen bearbeiten';
  end if;
  if not exists (select 1 from tip_join_requests
                 where round_id = p_round and user_id = p_user) then
    raise exception 'Anfrage nicht gefunden';
  end if;
  if p_accept then
    insert into tip_round_members (round_id, user_id)
    values (p_round, p_user) on conflict do nothing;
  end if;
  delete from tip_join_requests where round_id = p_round and user_id = p_user;
end$$;
