-- Waiver-Wire (Phase 4b): terminierte Abarbeitung von Spieler-Anträgen.
--
-- Bisher konnte jeder freie Spieler sofort per Free Agency geholt werden
-- (0006). Damit Drops nicht sofort vom Schnellsten abgegriffen werden,
-- kommt ein gedroppter Spieler auf den Waiver-Wire: dort ist er nur per
-- Antrag (Claim) holbar. Alle Anträge werden gesammelt und 2 Tage vor dem
-- nächsten Spieltag in Prioritätsreihenfolge abgearbeitet.
--
-- Priorität = umgekehrte Tabelle. Solange es serverseitig noch keine
-- kumulierten Saisonpunkte gibt (die Wertung läuft im Client aus
-- OpenLigaDB), nähern wir das über eine rollende Waiver-Priorität an:
-- Startwert = umgekehrte Draft-Reihenfolge (schwächster Erst-Draft zuerst),
-- danach rutscht jeder erfolgreiche Claim ans Ende. Das gibt schwächeren
-- Teams dauerhaft den Vortritt.
--
-- Echte Free Agents (nie gedraftet oder vom Wire gefallen) bleiben weiter
-- direkt holbar (fantasy_add_free_agent, 0006).

-- ---------------------------------------------------------------------
-- Schema-Erweiterungen
-- ---------------------------------------------------------------------

-- Letzte bereits abgearbeitete Spieltags-Runde (verhindert Doppelläufe).
alter table public.fantasy_leagues
  add column last_waiver_round int not null default 0;

-- Rollende Waiver-Priorität je Manager (1 = zuerst dran). NULL bis zur
-- ersten Abarbeitung, dann lazy initialisiert.
alter table public.fantasy_league_members
  add column waiver_priority int;

-- Spieler auf dem Wire: nach einem Drop claim-only bis [clears_at]
-- (= die zum Drop-Zeitpunkt nächste Waiver-Deadline).
create table public.fantasy_waiver_players (
  league_id uuid not null references public.fantasy_leagues (id) on delete cascade,
  player_id text not null references public.players (id),
  clears_at timestamptz not null,
  primary key (league_id, player_id)
);

alter table public.fantasy_waiver_players enable row level security;

create policy "Mitglieder sehen den Waiver-Wire"
  on public.fantasy_waiver_players for select
  using (public.is_fantasy_member(league_id));

-- Waiver-Anträge. Ein Manager kann mehrere stellen und per [rank] ordnen
-- (1 = wichtigster); ein gewonnener Antrag schiebt ihn ans Prioritätsende.
create table public.fantasy_waiver_claims (
  id             uuid primary key default gen_random_uuid(),
  league_id      uuid not null references public.fantasy_leagues (id) on delete cascade,
  manager_id     uuid not null references public.profiles (id),
  add_player_id  text not null references public.players (id),
  drop_player_id text references public.players (id),
  rank           int not null default 1,
  status         text not null default 'pending'
                 check (status in ('pending', 'won', 'lost', 'invalid', 'cancelled')),
  reason         text,
  created_at     timestamptz not null default now(),
  processed_at   timestamptz
);

create index fantasy_waiver_claims_league_idx
  on public.fantasy_waiver_claims (league_id, status);

alter table public.fantasy_waiver_claims enable row level security;

-- Anträge sind privat: jeder sieht nur die eigenen (wie bei Sleeper).
create policy "Eigene Waiver-Anträge"
  on public.fantasy_waiver_claims for select
  using (manager_id = auth.uid());
-- Schreiben nur über die RPCs unten.

alter publication supabase_realtime add table public.fantasy_waiver_players;
alter publication supabase_realtime add table public.fantasy_waiver_claims;

-- ---------------------------------------------------------------------
-- Zeitfenster: nächster Spieltag und Waiver-Deadline (2 Tage davor)
-- ---------------------------------------------------------------------
-- Deadline bezieht sich auf den ersten Anstoß des Spieltags. Liefert die
-- nächste Runde, deren Deadline noch in der Zukunft liegt.
create function public.fantasy_next_waiver_window(
  p_season int, out round int, out deadline timestamptz)
language sql stable as $$
  with rounds as (
    select f.round, min(f.kickoff) as first_kick
    from public.fixtures f
    where f.league_id = 'bundesliga' and f.season = p_season
    group by f.round
  )
  select r.round, r.first_kick - interval '2 days'
  from rounds r
  where r.first_kick - interval '2 days' > now()
  order by r.first_kick
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- Waiver-Priorität (lazy): umgekehrte Draft-Reihenfolge als Startwert.
-- ---------------------------------------------------------------------
create function public.fantasy_init_waiver_priority(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from fantasy_league_members
             where league_id = p_league_id and waiver_priority is not null) then
    return;
  end if;
  update fantasy_league_members m
    set waiver_priority = s.pri
  from (
    select user_id,
           row_number() over (order by draft_position desc nulls last, joined_at) as pri
    from fantasy_league_members where league_id = p_league_id
  ) s
  where m.league_id = p_league_id and m.user_id = s.user_id;
end$$;

-- ---------------------------------------------------------------------
-- Drop kommt jetzt auf den Wire (0006-Funktion ersetzt).
-- ---------------------------------------------------------------------
create or replace function public.fantasy_drop_player(
  p_league_id uuid, p_player_id text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_clears timestamptz;
begin
  if not exists (select 1 from fantasy_rosters
                 where league_id = p_league_id and player_id = p_player_id
                   and manager_id = auth.uid()) then
    raise exception 'Spieler ist nicht in deinem Kader';
  end if;

  delete from fantasy_rosters
    where league_id = p_league_id and player_id = p_player_id
      and manager_id = auth.uid();

  -- Auf den Wire setzen, solange es einen nächsten Waiver-Termin gibt.
  -- Ohne anstehenden Spieltag (Saison vorbei) wird der Spieler sofort frei.
  select season into v_season from fantasy_leagues where id = p_league_id;
  select w.deadline into v_clears
    from public.fantasy_next_waiver_window(v_season) w;
  if v_clears is not null then
    insert into fantasy_waiver_players (league_id, player_id, clears_at)
    values (p_league_id, p_player_id, v_clears)
    on conflict (league_id, player_id) do update set clears_at = excluded.clears_at;
  end if;
end$$;

-- ---------------------------------------------------------------------
-- Direkt-Aufnahme respektiert jetzt den Wire (0006-Funktion ersetzt).
-- ---------------------------------------------------------------------
create or replace function public.fantasy_add_free_agent(
  p_league_id uuid, p_add_player_id text, p_drop_player_id text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_roster jsonb; v_locked boolean; v_count int;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  select season, roster into v_season, v_roster
    from fantasy_leagues where id = p_league_id for update;

  if not exists (select 1 from players where id = p_add_player_id) then
    raise exception 'Spieler unbekannt';
  end if;
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_add_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;

  -- Auf dem Wire? Dann nur per Waiver-Antrag, nicht direkt.
  if exists (select 1 from fantasy_waiver_players
             where league_id = p_league_id and player_id = p_add_player_id
               and clears_at > now()) then
    raise exception 'Spieler ist auf dem Waiver-Wire – nur per Antrag holbar';
  end if;

  select public.fantasy_is_locked(birth_date, is_foreign_newcomer, v_season, now())
    into v_locked from players where id = p_add_player_id;
  if v_locked then
    raise exception 'Spieler ist gesperrt (U20/Neuzugang, für den U20-Draft reserviert)';
  end if;

  if p_drop_player_id is not null then
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and player_id = p_drop_player_id
                     and manager_id = auth.uid()) then
      raise exception 'Abzugebender Spieler ist nicht in deinem Kader';
    end if;
    delete from fantasy_rosters
      where league_id = p_league_id and player_id = p_drop_player_id
        and manager_id = auth.uid();
  end if;

  select count(*) into v_count from fantasy_rosters
    where league_id = p_league_id and manager_id = auth.uid();
  if v_count >= public.fantasy_squad_size(v_roster) then
    raise exception 'Kader voll – du musst einen Spieler abgeben';
  end if;

  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
  values (p_league_id, auth.uid(), p_add_player_id, 'fa');
end$$;

-- ---------------------------------------------------------------------
-- Antrag stellen / stornieren
-- ---------------------------------------------------------------------
create function public.fantasy_submit_waiver_claim(
  p_league_id uuid, p_add_player_id text,
  p_drop_player_id text default null, p_rank int default 1)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_locked boolean; v_id uuid;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  select season into v_season from fantasy_leagues where id = p_league_id;

  -- Antrag nur auf Spieler, die aktuell auf dem Wire liegen.
  if not exists (select 1 from fantasy_waiver_players
                 where league_id = p_league_id and player_id = p_add_player_id
                   and clears_at > now()) then
    raise exception 'Spieler ist nicht auf dem Waiver-Wire';
  end if;

  select public.fantasy_is_locked(birth_date, is_foreign_newcomer, v_season, now())
    into v_locked from players where id = p_add_player_id;
  if v_locked then
    raise exception 'Spieler ist gesperrt (U20/Neuzugang)';
  end if;

  if p_drop_player_id is not null and not exists (
       select 1 from fantasy_rosters
       where league_id = p_league_id and player_id = p_drop_player_id
         and manager_id = auth.uid()) then
    raise exception 'Abzugebender Spieler ist nicht in deinem Kader';
  end if;

  insert into fantasy_waiver_claims
    (league_id, manager_id, add_player_id, drop_player_id, rank)
  values
    (p_league_id, auth.uid(), p_add_player_id, p_drop_player_id, greatest(p_rank, 1))
  returning id into v_id;
  return v_id;
end$$;

create function public.fantasy_cancel_waiver_claim(p_claim_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update fantasy_waiver_claims
    set status = 'cancelled', processed_at = now()
    where id = p_claim_id and manager_id = auth.uid() and status = 'pending';
  if not found then
    raise exception 'Antrag nicht gefunden oder schon abgearbeitet';
  end if;
end$$;

-- ---------------------------------------------------------------------
-- Abarbeitung einer Liga in Prioritätsreihenfolge (rolling waiver)
-- ---------------------------------------------------------------------
create function public.fantasy_process_waivers(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_claim   fantasy_waiver_claims%rowtype;
  v_roster  jsonb; v_squad int; v_have int; v_frees int;
  v_guard   int := 0;
begin
  perform public.fantasy_init_waiver_priority(p_league_id);
  select roster into v_roster from fantasy_leagues where id = p_league_id for update;
  v_squad := public.fantasy_squad_size(v_roster);

  loop
    v_guard := v_guard + 1;
    exit when v_guard > 10000;

    -- Bester gewährbarer Antrag: Manager-Priorität, dann eigener Rang,
    -- dann Eingangszeit. Nur Spieler, die noch auf dem Wire und frei sind.
    select c.* into v_claim
    from fantasy_waiver_claims c
    join fantasy_league_members m
      on m.league_id = c.league_id and m.user_id = c.manager_id
    where c.league_id = p_league_id and c.status = 'pending'
      and exists (select 1 from fantasy_waiver_players w
                  where w.league_id = c.league_id and w.player_id = c.add_player_id)
      and not exists (select 1 from fantasy_rosters r
                      where r.league_id = c.league_id and r.player_id = c.add_player_id)
    order by m.waiver_priority asc, c.rank asc, c.created_at asc
    limit 1;
    exit when not found;

    -- Wird ein gültiger Drop mitgegeben, schafft er Platz.
    v_frees := 0;
    if v_claim.drop_player_id is not null and exists (
         select 1 from fantasy_rosters
         where league_id = p_league_id and player_id = v_claim.drop_player_id
           and manager_id = v_claim.manager_id) then
      v_frees := 1;
    end if;

    select count(*) into v_have from fantasy_rosters
      where league_id = p_league_id and manager_id = v_claim.manager_id;

    if v_have - v_frees >= v_squad then
      update fantasy_waiver_claims
        set status = 'invalid', reason = 'Kader voll – Drop nötig', processed_at = now()
        where id = v_claim.id;
      continue;
    end if;

    -- Gewähren: Drop, Aufnahme, Antrag schließen, Spieler vom Wire nehmen.
    if v_frees = 1 then
      delete from fantasy_rosters
        where league_id = p_league_id and player_id = v_claim.drop_player_id
          and manager_id = v_claim.manager_id;
    end if;
    insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
    values (p_league_id, v_claim.manager_id, v_claim.add_player_id, 'waiver');

    update fantasy_waiver_claims
      set status = 'won', processed_at = now() where id = v_claim.id;
    delete from fantasy_waiver_players
      where league_id = p_league_id and player_id = v_claim.add_player_id;

    -- Rolling: Gewinner ans Ende der Priorität.
    update fantasy_league_members
      set waiver_priority = (select coalesce(max(waiver_priority), 0) + 1
                             from fantasy_league_members where league_id = p_league_id)
      where league_id = p_league_id and user_id = v_claim.manager_id;
  end loop;

  -- Übrige offene Anträge: Spieler ging an höhere Priorität bzw. ist weg.
  update fantasy_waiver_claims
    set status = 'lost', reason = 'Spieler anderweitig vergeben', processed_at = now()
    where league_id = p_league_id and status = 'pending';

  -- Aufräumen: abgelaufene Wire-Einträge freigeben (= echte Free Agents).
  delete from fantasy_waiver_players
    where league_id = p_league_id and clears_at <= now();
end$$;

-- ---------------------------------------------------------------------
-- Cron-Treiber: läuft alle 10 Min, arbeitet fällige Ligen einmal je Runde ab.
-- ---------------------------------------------------------------------
create function public.fantasy_process_due_waivers()
returns void language plpgsql security definer set search_path = public as $$
declare
  l record; v_round int; v_deadline timestamptz;
begin
  for l in select id, season, last_waiver_round from fantasy_leagues loop
    select w.round, w.deadline into v_round, v_deadline
      from public.fantasy_next_waiver_window(l.season) w;
    if v_deadline is not null and now() >= v_deadline
       and l.last_waiver_round < v_round then
      perform public.fantasy_process_waivers(l.id);
      update fantasy_leagues set last_waiver_round = v_round where id = l.id;
    end if;
  end loop;
end$$;

select cron.schedule('fantasy-waivers', '*/10 * * * *',
  $$ select public.fantasy_process_due_waivers(); $$);
