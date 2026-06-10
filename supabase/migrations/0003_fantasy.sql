-- Fantasy-Modus (Phase 1): Ligen, Mitglieder (Manager) und Spielerpool.
-- Draft-Picks und Kader folgen in einer späteren Migration.
--
-- Aufbau und RLS bewusst analog zum Tippspiel (0001/0002): private Liga
-- mit Einladungscode, Beitritt per RPC, Ersteller wird per Trigger
-- automatisch Mitglied.

-- ---------------------------------------------------------------------
-- Globaler Spielerpool (für alle Ligen gleich)
-- ---------------------------------------------------------------------
create table public.players (
  id                   text primary key,         -- 'seed:5'
  name                 text not null,
  position             text not null
                       check (position in ('gk', 'def', 'mid', 'fwd')),
  club                 text not null,
  birth_date           date not null,
  nationality          text not null,            -- ISO-Code für Flagge
  is_foreign_newcomer  boolean not null default false
);

alter table public.players enable row level security;

create policy "Spielerpool ist lesbar"
  on public.players for select using (true);
-- Schreiben nur über service_role (Seed/Sync), keine weitere Policy.

-- ---------------------------------------------------------------------
-- Fantasy-Ligen
-- ---------------------------------------------------------------------
create table public.fantasy_leagues (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null check (char_length(name) between 3 and 64),
  mode                text not null check (mode in ('liga', 'dynasty')),
  season              int  not null,
  draft_pick_seconds  int  not null default 60,
  scoring             jsonb not null default '{}',
  roster              jsonb not null default '{}',
  invite_code         text unique not null default encode(gen_random_bytes(6), 'hex'),
  draft_status        text not null default 'setup'
                      check (draft_status in ('setup', 'drafting', 'done')),
  created_by          uuid not null references public.profiles (id),
  created_at          timestamptz not null default now()
);

create table public.fantasy_league_members (
  league_id      uuid not null references public.fantasy_leagues (id) on delete cascade,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  draft_position int,
  joined_at      timestamptz not null default now(),
  primary key (league_id, user_id)
);

alter table public.fantasy_leagues enable row level security;
alter table public.fantasy_league_members enable row level security;

create function public.is_fantasy_member(p_league_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from fantasy_league_members
    where league_id = p_league_id and user_id = auth.uid()
  );
$$;

create policy "Mitglieder sehen ihre Fantasy-Ligen"
  on public.fantasy_leagues for select
  using (public.is_fantasy_member(id) or created_by = auth.uid());

create policy "Eingeloggte Nutzer erstellen Fantasy-Ligen"
  on public.fantasy_leagues for insert
  with check (auth.uid() = created_by);

create policy "Ersteller verwaltet seine Fantasy-Liga"
  on public.fantasy_leagues for update
  using (created_by = auth.uid());

create policy "Mitglieder sehen Manager-Liste"
  on public.fantasy_league_members for select
  using (public.is_fantasy_member(league_id));

-- Ersteller automatisch als Manager eintragen.
create function public.add_fantasy_creator_as_member()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into fantasy_league_members (league_id, user_id)
  values (new.id, new.created_by)
  on conflict do nothing;
  return new;
end;
$$;

create trigger fantasy_leagues_add_creator
  after insert on public.fantasy_leagues
  for each row execute function public.add_fantasy_creator_as_member();

-- Beitritt per Einladungscode.
create function public.join_fantasy_league(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_league_id uuid;
  v_status    text;
begin
  select id, draft_status into v_league_id, v_status
  from fantasy_leagues where invite_code = p_invite_code;
  if v_league_id is null then
    raise exception 'Ungültiger Einladungscode';
  end if;
  if v_status <> 'setup' then
    raise exception 'Der Draft dieser Liga hat bereits begonnen';
  end if;
  insert into fantasy_league_members (league_id, user_id)
  values (v_league_id, auth.uid())
  on conflict do nothing;
  return v_league_id;
end;
$$;
