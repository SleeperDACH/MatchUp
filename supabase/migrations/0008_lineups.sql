-- Manuelle Aufstellung (Phase 5): Startelf pro Spieltag selbst wählen.
--
-- Bisher zählte automatisch die „beste Elf" des Spieltags (bestEleven im
-- Client). Jetzt kann jeder Manager seine Startelf je Spieltag selbst
-- festlegen; ohne gespeicherte Aufstellung bleibt die automatische beste
-- Elf als Fallback.
--
-- Formation ist fix aus der roster-Konfiguration (Standard 1/4/4/2 = 11):
-- pro Position höchstens so viele Starter wie Slots. Unterbesetzen ist
-- erlaubt (geht nur zu Lasten des Managers).
--
-- Deadline serverseitig (CLAUDE.md): Aufstellung nur vor dem ersten Anstoß
-- des Spieltags. Grundlage ist die gespiegelte fixtures-Tabelle.

create table public.fantasy_lineups (
  league_id  uuid not null references public.fantasy_leagues (id) on delete cascade,
  manager_id uuid not null references public.profiles (id),
  season     int  not null,
  round      int  not null,
  player_ids text[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (league_id, manager_id, season, round)
);

create index fantasy_lineups_round_idx
  on public.fantasy_lineups (league_id, round);

alter table public.fantasy_lineups enable row level security;

-- Mitglieder sehen alle Aufstellungen ihrer Liga (für die Liga-Tabelle).
create policy "Mitglieder sehen Aufstellungen"
  on public.fantasy_lineups for select
  using (public.is_fantasy_member(league_id));
-- Schreiben nur über fantasy_set_lineup (Deadline + Formation serverseitig).

alter publication supabase_realtime add table public.fantasy_lineups;

-- ---------------------------------------------------------------------
-- Deadline = erster Anstoß des Spieltags (aus der gespiegelten fixtures).
-- ---------------------------------------------------------------------
create function public.fantasy_round_deadline(p_season int, p_round int)
returns timestamptz language sql stable as $$
  select min(kickoff) from public.fixtures
   where league_id = 'bundesliga' and season = p_season and round = p_round;
$$;

-- ---------------------------------------------------------------------
-- Aufstellung setzen: eigener Kader, Formation, vor Anstoß.
-- ---------------------------------------------------------------------
create function public.fantasy_set_lineup(
  p_league_id uuid, p_round int, p_player_ids text[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_roster jsonb; v_deadline timestamptz;
  v_gk int; v_def int; v_mid int; v_fwd int;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  select season, roster into v_season, v_roster
    from fantasy_leagues where id = p_league_id;

  v_deadline := public.fantasy_round_deadline(v_season, p_round);
  if v_deadline is not null and now() >= v_deadline then
    raise exception 'Aufstellung ist gesperrt – der Spieltag hat begonnen';
  end if;

  -- Nur Spieler aus dem eigenen Kader.
  if exists (
    select 1 from unnest(p_player_ids) pid
    where not exists (
      select 1 from fantasy_rosters r
      where r.league_id = p_league_id and r.manager_id = auth.uid()
        and r.player_id = pid)) then
    raise exception 'Aufstellung enthält Spieler außerhalb deines Kaders';
  end if;

  -- Formation: pro Position höchstens die Slot-Anzahl.
  select count(*) filter (where p.position = 'gk'),
         count(*) filter (where p.position = 'def'),
         count(*) filter (where p.position = 'mid'),
         count(*) filter (where p.position = 'fwd')
    into v_gk, v_def, v_mid, v_fwd
    from players p where p.id = any(p_player_ids);

  if v_gk  > coalesce((v_roster->>'gk')::int, 1)
   or v_def > coalesce((v_roster->>'def')::int, 4)
   or v_mid > coalesce((v_roster->>'mid')::int, 4)
   or v_fwd > coalesce((v_roster->>'fwd')::int, 2) then
    raise exception 'Aufstellung verletzt die Formation (zu viele auf einer Position)';
  end if;

  insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
  values (p_league_id, auth.uid(), v_season, p_round, p_player_ids)
  on conflict (league_id, manager_id, season, round)
    do update set player_ids = excluded.player_ids, updated_at = now();
end$$;
