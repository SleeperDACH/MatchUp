-- Fantasy-Snake-Draft (Phase 2): server-autoritative Draft-Logik.
--
-- Entscheidungen:
-- * Quelle der Wahrheit ist die DB: picks_made + draft_position bestimmen
--   per Snake-Formel, wer am Zug ist; current_pick_deadline die Pickzeit.
-- * Picks laufen ausschließlich über RPCs (security definer, mit Row-Lock
--   auf der Liga), damit keine Doppel-Picks oder Manipulation möglich sind.
-- * Auto-Pick bei Ablauf: jeder Mitspieler-Client darf einen abgelaufenen
--   Zug auslösen (für Live-Drafts), zusätzlich ein pg_cron-Sicherheitsnetz
--   jede Minute (für Slow-Drafts, wenn niemand online ist).

-- ---------------------------------------------------------------------
-- Draft-Status auf der Liga
-- ---------------------------------------------------------------------
alter table public.fantasy_leagues
  add column picks_made           int not null default 0,
  add column current_pick_deadline timestamptz,
  add column draft_started_at     timestamptz;

-- ---------------------------------------------------------------------
-- Picks (= Kader: alle Picks eines Managers bilden seinen Kader)
-- ---------------------------------------------------------------------
create table public.draft_picks (
  league_id   uuid not null references public.fantasy_leagues (id) on delete cascade,
  pick_number int  not null,                 -- 1-basiert, global in der Liga
  round       int  not null,
  manager_id  uuid not null references public.profiles (id),
  player_id   text not null references public.players (id),
  is_auto     boolean not null default false,
  created_at  timestamptz not null default now(),
  primary key (league_id, pick_number),
  unique (league_id, player_id)              -- kein Spieler doppelt
);

create index draft_picks_manager_idx
  on public.draft_picks (league_id, manager_id);

alter table public.draft_picks enable row level security;

create policy "Mitglieder sehen Draft-Picks"
  on public.draft_picks for select
  using (public.is_fantasy_member(league_id));
-- Schreiben nur über die RPCs unten.

-- ---------------------------------------------------------------------
-- Kadergröße aus der roster-Konfiguration (= Anzahl Draft-Runden)
-- ---------------------------------------------------------------------
create function public.fantasy_squad_size(p_roster jsonb)
returns int language sql immutable as $$
  select coalesce((p_roster->>'gk')::int, 1)
       + coalesce((p_roster->>'def')::int, 4)
       + coalesce((p_roster->>'mid')::int, 4)
       + coalesce((p_roster->>'fwd')::int, 2)
       + coalesce((p_roster->>'bench')::int, 5);
$$;

-- Wer ist beim Stand p_picks_made (0-basiert) am Zug? Snake-Reihenfolge.
create function public.fantasy_current_manager(p_league_id uuid)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  v_p int; v_n int; v_round0 int; v_pos int; v_slot int; v_manager uuid;
begin
  select picks_made into v_p from fantasy_leagues where id = p_league_id;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  if v_n = 0 then return null; end if;
  v_round0 := v_p / v_n;
  v_pos := v_p % v_n;
  if v_round0 % 2 = 0 then
    v_slot := v_pos + 1;            -- Hinrunde: 1..N
  else
    v_slot := v_n - v_pos;          -- Rückrunde: N..1
  end if;
  select user_id into v_manager
  from fantasy_league_members
  where league_id = p_league_id and draft_position = v_slot;
  return v_manager;
end$$;

-- Internes Vorrücken: Pick eintragen + Zähler/Deadline aktualisieren.
create function public.fantasy_advance(
  p_league_id uuid, p_manager uuid, p_player text, p_is_auto boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_p int; v_n int; v_squad int; v_total int; v_secs int;
begin
  select picks_made, draft_pick_seconds, public.fantasy_squad_size(roster)
    into v_p, v_secs, v_squad
    from fantasy_leagues where id = p_league_id;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  v_total := v_n * v_squad;

  insert into draft_picks (league_id, pick_number, round, manager_id, player_id, is_auto)
  values (p_league_id, v_p + 1, (v_p / v_n) + 1, p_manager, p_player, p_is_auto);

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

-- Draft starten (nur Admin/Ersteller).
create function public.start_fantasy_draft(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_n int; v_secs int;
begin
  select created_by, draft_status, draft_pick_seconds
    into v_created_by, v_status, v_secs
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den Draft starten';
  end if;
  if v_status <> 'setup' then
    raise exception 'Der Draft wurde bereits gestartet';
  end if;
  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  if v_n < 1 then raise exception 'Mindestens ein Manager nötig'; end if;

  -- Zufällige Draft-Reihenfolge auslosen.
  with shuffled as (
    select user_id, row_number() over (order by random()) as pos
    from fantasy_league_members where league_id = p_league_id
  )
  update fantasy_league_members m
    set draft_position = s.pos
    from shuffled s
    where m.league_id = p_league_id and m.user_id = s.user_id;

  update fantasy_leagues
    set draft_status = 'drafting',
        picks_made = 0,
        draft_started_at = now(),
        current_pick_deadline = now() + (v_secs || ' seconds')::interval
    where id = p_league_id;
end$$;

-- Manueller Pick durch den Manager, der am Zug ist.
create function public.fantasy_make_pick(p_league_id uuid, p_player_id text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_manager uuid; v_exists int;
begin
  select draft_status into v_status from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then raise exception 'Der Draft läuft nicht'; end if;

  v_manager := public.fantasy_current_manager(p_league_id);
  if auth.uid() <> v_manager then
    raise exception 'Du bist nicht am Zug';
  end if;

  select count(*) into v_exists from players where id = p_player_id;
  if v_exists = 0 then raise exception 'Spieler unbekannt'; end if;
  if exists (select 1 from draft_picks
             where league_id = p_league_id and player_id = p_player_id) then
    raise exception 'Spieler ist bereits gedraftet';
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, p_player_id, false);
end$$;

-- Auto-Pick, wenn die Pickzeit abgelaufen ist. Aufrufbar durch
-- Liga-Mitglieder (Live) oder den Cron (service_role, auth.uid() null).
create function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
begin
  select draft_status, current_pick_deadline
    into v_status, v_deadline
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;
  if v_deadline is null or now() <= v_deadline then return false; end if;

  if auth.uid() is not null and not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  v_manager := public.fantasy_current_manager(p_league_id);

  -- "Bester verfügbarer" — vorläufig deterministisch nach Name.
  select id into v_player from players
    where id not in (select player_id from draft_picks where league_id = p_league_id)
    order by name limit 1;

  if v_player is null then
    -- Pool erschöpft: Draft sauber beenden.
    update fantasy_leagues
      set draft_status = 'done', current_pick_deadline = null
      where id = p_league_id;
    return false;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, v_player, true);
  return true;
end$$;

-- Cron-Sicherheitsnetz: läuft jede Minute über alle laufenden Drafts.
create function public.fantasy_autopick_all()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from fantasy_leagues
           where draft_status = 'drafting' and current_pick_deadline < now() loop
    perform public.fantasy_autopick_if_expired(r.id);
  end loop;
end$$;

select cron.schedule('fantasy-autopick', '* * * * *',
  $$ select public.fantasy_autopick_all(); $$);

-- Realtime für Draft-Raum (respektiert RLS des Abonnenten).
alter publication supabase_realtime add table public.draft_picks;
alter publication supabase_realtime add table public.fantasy_leagues;

-- ---------------------------------------------------------------------
-- Spielerpool-Seed (Starter-Datensatz Bundesliga). Quelle der Wahrheit
-- ist diese Tabelle; ein echter Feed ersetzt/ergänzt sie später.
-- Geburtsdaten auf das Jahr genau (für die U20-Logik ausreichend).
-- ---------------------------------------------------------------------
insert into public.players (id, name, position, club, birth_date, nationality, is_foreign_newcomer) values
  ('seed:1','Manuel Neuer','gk','FC Bayern München','1986-01-01','de',false),
  ('seed:2','Joshua Kimmich','mid','FC Bayern München','1995-01-01','de',false),
  ('seed:3','Alphonso Davies','def','FC Bayern München','2000-01-01','ca',false),
  ('seed:4','Harry Kane','fwd','FC Bayern München','1993-01-01','gb-eng',false),
  ('seed:5','Jamal Musiala','mid','FC Bayern München','2003-01-01','de',false),
  ('seed:6','Aleksandar Pavlović','mid','FC Bayern München','2004-01-01','de',false),
  ('seed:25','Michael Olise','mid','FC Bayern München','2001-01-01','fr',true),
  ('seed:26','Dayot Upamecano','def','FC Bayern München','1998-01-01','fr',false),
  ('seed:27','Leroy Sané','fwd','FC Bayern München','1996-01-01','de',false),
  ('seed:28','Serge Gnabry','fwd','FC Bayern München','1995-01-01','de',false),
  ('seed:7','Granit Xhaka','mid','Bayer 04 Leverkusen','1992-01-01','ch',false),
  ('seed:8','Florian Wirtz','mid','Bayer 04 Leverkusen','2003-01-01','de',false),
  ('seed:9','Jeremie Frimpong','def','Bayer 04 Leverkusen','2000-01-01','nl',false),
  ('seed:10','Victor Boniface','fwd','Bayer 04 Leverkusen','2000-01-01','ng',false),
  ('seed:29','Jonathan Tah','def','Bayer 04 Leverkusen','1996-01-01','de',false),
  ('seed:30','Patrik Schick','fwd','Bayer 04 Leverkusen','1996-01-01','cz',false),
  ('seed:31','Alejandro Grimaldo','def','Bayer 04 Leverkusen','1995-01-01','es',false),
  ('seed:11','Gregor Kobel','gk','Borussia Dortmund','1997-01-01','ch',false),
  ('seed:12','Nico Schlotterbeck','def','Borussia Dortmund','1999-01-01','de',false),
  ('seed:13','Julian Brandt','mid','Borussia Dortmund','1996-01-01','de',false),
  ('seed:14','Karim Adeyemi','fwd','Borussia Dortmund','2002-01-01','de',false),
  ('seed:32','Marcel Sabitzer','mid','Borussia Dortmund','1994-01-01','at',false),
  ('seed:33','Serhou Guirassy','fwd','Borussia Dortmund','1996-01-01','gn',true),
  ('seed:34','Julian Ryerson','def','Borussia Dortmund','1997-01-01','no',false),
  ('seed:15','Angelo Stiller','mid','VfB Stuttgart','2001-01-01','de',false),
  ('seed:16','Deniz Undav','fwd','VfB Stuttgart','1996-01-01','de',false),
  ('seed:35','Alexander Nübel','gk','VfB Stuttgart','1996-01-01','de',false),
  ('seed:36','Maximilian Mittelstädt','def','VfB Stuttgart','1997-01-01','de',false),
  ('seed:37','Chris Führich','mid','VfB Stuttgart','1998-01-01','de',false),
  ('seed:17','Benjamin Šeško','fwd','RB Leipzig','2003-01-01','si',false),
  ('seed:18','Xavi Simons','mid','RB Leipzig','2003-01-01','nl',true),
  ('seed:38','Willi Orbán','def','RB Leipzig','1992-01-01','hu',false),
  ('seed:39','Loïs Openda','fwd','RB Leipzig','2000-01-01','be',false),
  ('seed:40','David Raum','def','RB Leipzig','1998-01-01','de',false),
  ('seed:19','Hugo Ekitiké','fwd','Eintracht Frankfurt','2002-01-01','fr',true),
  ('seed:20','Mario Götze','mid','Eintracht Frankfurt','1992-01-01','de',false),
  ('seed:41','Kevin Trapp','gk','Eintracht Frankfurt','1990-01-01','de',false),
  ('seed:42','Omar Marmoush','fwd','Eintracht Frankfurt','1999-01-01','eg',false),
  ('seed:21','Assan Ouédraogo','mid','RB Leipzig','2006-01-01','de',false),
  ('seed:22','Paris Brunner','fwd','AS Monaco','2006-01-01','de',true),
  ('seed:23','Nestory Irankunda','fwd','FC Bayern München','2006-01-01','au',true),
  ('seed:24','Max Moerstedt','fwd','TSG Hoffenheim','2005-01-01','de',false),
  ('seed:43','Florian Neuhaus','mid','Borussia Mönchengladbach','1997-01-01','de',false),
  ('seed:44','Jonas Wind','fwd','VfL Wolfsburg','1999-01-01','dk',false),
  ('seed:45','Vincenzo Grifo','mid','SC Freiburg','1993-01-01','it',false),
  ('seed:46','Marvin Ducksch','fwd','SV Werder Bremen','1994-01-01','de',false),
  ('seed:47','Andrej Kramarić','fwd','TSG Hoffenheim','1991-01-01','hr',false),
  ('seed:48','Jonathan Burkardt','fwd','1. FSV Mainz 05','2000-01-01','de',false)
on conflict (id) do nothing;
