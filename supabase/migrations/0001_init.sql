-- Tippspiel-Schema (Phase 1).
-- Anwenden mit der Supabase CLI: `supabase db push`
-- oder per Copy & Paste in den SQL-Editor des Supabase-Dashboards.
--
-- Designentscheidungen:
-- * Fixtures werden serverseitig aus dem Sportdaten-Provider gespiegelt
--   (Edge Function / Cron), damit die Tipp-Deadline (Anstoßzeit) in den
--   RLS-Policies verbindlich geprüft werden kann. Clients dürfen
--   Fixtures nur lesen.
-- * Das Punkteschema liegt als JSONB pro Tipprunde — gleiche Mechanik
--   für andere Ligen/Sportarten später.
-- * IDs von Fixtures sind Provider-qualifizierte Texte
--   (z. B. 'openligadb:77554'), identisch zum App-Code.

-- ---------------------------------------------------------------------
-- Profile (1:1 zu auth.users)
-- ---------------------------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  username   text unique not null check (char_length(username) between 3 and 24),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Profile sind öffentlich lesbar"
  on public.profiles for select using (true);

create policy "Eigenes Profil anlegen"
  on public.profiles for insert with check (auth.uid() = id);

create policy "Eigenes Profil ändern"
  on public.profiles for update using (auth.uid() = id);

-- ---------------------------------------------------------------------
-- Gespiegelte Spieldaten (nur lesbar für Clients)
-- ---------------------------------------------------------------------
create table public.fixtures (
  id         text primary key,            -- 'openligadb:77554'
  league_id  text not null,               -- 'bundesliga'
  season     int  not null,               -- Startjahr, z. B. 2025
  round      int  not null,               -- Spieltag / Week
  kickoff    timestamptz not null,
  home_name  text not null,
  away_name  text not null,
  home_score int,
  away_score int,
  status     text not null default 'scheduled'
             check (status in ('scheduled', 'live', 'finished'))
);

create index fixtures_league_season_round_idx
  on public.fixtures (league_id, season, round);

alter table public.fixtures enable row level security;

create policy "Fixtures sind öffentlich lesbar"
  on public.fixtures for select using (true);
-- Schreiben nur über service_role (Sync-Job), keine Insert/Update-Policy.

-- ---------------------------------------------------------------------
-- Tipprunden (à la Kicktipp: private Runde mit Einladungscode)
-- ---------------------------------------------------------------------
create table public.tip_rounds (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 3 and 64),
  league_id   text not null,
  season      int  not null,
  invite_code text unique not null default encode(gen_random_bytes(6), 'hex'),
  scoring     jsonb not null default '{"exact": 4, "goalDiff": 3, "tendency": 2}',
  created_by  uuid not null references public.profiles (id),
  created_at  timestamptz not null default now()
);

create table public.tip_round_members (
  round_id  uuid not null references public.tip_rounds (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (round_id, user_id)
);

alter table public.tip_rounds enable row level security;
alter table public.tip_round_members enable row level security;

create function public.is_round_member(p_round_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tip_round_members
    where round_id = p_round_id and user_id = auth.uid()
  );
$$;

create policy "Mitglieder sehen ihre Tipprunden"
  on public.tip_rounds for select
  using (public.is_round_member(id) or created_by = auth.uid());

create policy "Eingeloggte Nutzer erstellen Tipprunden"
  on public.tip_rounds for insert
  with check (auth.uid() = created_by);

create policy "Mitglieder sehen Mitgliederliste"
  on public.tip_round_members for select
  using (public.is_round_member(round_id));

-- Beitritt erfolgt über die RPC join_tip_round (per Einladungscode),
-- nicht über direkte Inserts.
create function public.join_tip_round(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_round_id uuid;
begin
  select id into v_round_id from tip_rounds where invite_code = p_invite_code;
  if v_round_id is null then
    raise exception 'Ungültiger Einladungscode';
  end if;
  insert into tip_round_members (round_id, user_id)
  values (v_round_id, auth.uid())
  on conflict do nothing;
  return v_round_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Tipps — Deadline wird serverseitig erzwungen: Tippen nur vor Anstoß.
-- ---------------------------------------------------------------------
create table public.tips (
  round_id   uuid not null references public.tip_rounds (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  fixture_id text not null references public.fixtures (id),
  home_goals int  not null check (home_goals between 0 and 99),
  away_goals int  not null check (away_goals between 0 and 99),
  updated_at timestamptz not null default now(),
  primary key (round_id, user_id, fixture_id)
);

alter table public.tips enable row level security;

create function public.fixture_not_started(p_fixture_id text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from fixtures
    where id = p_fixture_id and kickoff > now()
  );
$$;

create policy "Eigene Tipps immer sehen, fremde erst nach Anstoß"
  on public.tips for select
  using (
    user_id = auth.uid()
    or (public.is_round_member(round_id)
        and not public.fixture_not_started(fixture_id))
  );

create policy "Tippen nur als Mitglied und vor Anstoß"
  on public.tips for insert
  with check (
    user_id = auth.uid()
    and public.is_round_member(round_id)
    and public.fixture_not_started(fixture_id)
  );

create policy "Tipp ändern nur vor Anstoß"
  on public.tips for update
  using (user_id = auth.uid())
  with check (public.fixture_not_started(fixture_id));

create policy "Tipp löschen nur vor Anstoß"
  on public.tips for delete
  using (user_id = auth.uid() and public.fixture_not_started(fixture_id));

-- ---------------------------------------------------------------------
-- Tabelle/Rangliste: Punkte je Mitglied und Tipprunde.
-- Identische Wertungslogik wie lib/features/tippspiel/logic/tip_scoring.dart.
-- ---------------------------------------------------------------------
create view public.tip_round_standings as
select
  t.round_id,
  t.user_id,
  p.username,
  count(*) filter (where f.status = 'finished')          as scored_tips,
  coalesce(sum(
    case
      when f.status <> 'finished' then 0
      when t.home_goals = f.home_score and t.away_goals = f.away_score
        then (r.scoring ->> 'exact')::int
      when t.home_goals - t.away_goals = f.home_score - f.away_score
        then (r.scoring ->> 'goalDiff')::int
      when sign(t.home_goals - t.away_goals) = sign(f.home_score - f.away_score)
        then (r.scoring ->> 'tendency')::int
      else 0
    end), 0)                                             as points
from public.tips t
join public.fixtures f   on f.id = t.fixture_id
join public.tip_rounds r on r.id = t.round_id
join public.profiles p   on p.id = t.user_id
group by t.round_id, t.user_id, p.username;
