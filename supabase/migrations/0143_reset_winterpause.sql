-- **Reset zur Winterpause** (20.10.2026, auf Ansage).
--
-- Eine Ligaeinstellung, beim Erstellen und später änderbar, solange der Reset
-- noch nicht stattgefunden hat. Ist sie an, gilt am **24.12. der Saison**
-- (00:00 Europe/Berlin — in 2026/27 liegt das zwischen Spieltag 14 am 19.12.
-- und Spieltag 15 am 09.01.):
--
--   * **Die Tabelle bleibt.** Sie wird aus den gespeicherten Aufstellungen
--     gerechnet, und die abgepfiffenen Spieltage fasst hier nichts an.
--   * **Alle Kader werden geleert**, offene Trades und Waiver-Anträge
--     verfallen, Wunschlisten aus dem ersten Draft fallen weg.
--   * Die Liga steht auf `draft_status = 'reset'`: Niemand kann Spieler holen
--     (Trigger auf `fantasy_rosters` und `fantasy_waiver_claims`), Beitritte
--     laufen wie nach einem Draft (die Funktionen prüfen auf `'setup'`).
--   * Der Admin startet den **Reset-Draft** (`fantasy_reset_draft_starten`),
--     Phase `reset`, Snake, Runde 1 vom Tabellenletzten zum Ersten. Die
--     Reihenfolge rechnet die App aus derselben Tabelle, die sie anzeigt — die
--     Wertung steht in Dart, eine dritte Fassung in SQL wäre die nächste
--     Stelle, an der zwei Tabellen auseinanderlaufen.
--   * Runden und Zeit je Pick kommen aus der Liga und sind vor dem Start
--     änderbar (dasselbe Start-Blatt wie beim ersten Draft).

alter table public.fantasy_leagues
  add column if not exists reset_aktiv boolean not null default false,
  add column if not exists reset_erfolgt_at timestamptz;

alter table public.fantasy_leagues
  drop constraint if exists fantasy_leagues_draft_status_check;
alter table public.fantasy_leagues
  add constraint fantasy_leagues_draft_status_check
  check (draft_status in ('setup', 'reset', 'drafting', 'done'));

alter table public.fantasy_leagues
  drop constraint if exists fantasy_leagues_draft_phase_check;
alter table public.fantasy_leagues
  add constraint fantasy_leagues_draft_phase_check
  check (draft_phase in ('startup', 'u20', 'reset'));

-- **Eigene Position für den Reset-Draft.** `draft_position` trägt auch die
-- Duell-Paarungen (die App sortiert den Round-Robin danach); sie zu
-- überschreiben verschöbe rückwirkend jedes Duell der Hinrunde — und damit
-- die Tabelle, die ausdrücklich bleiben soll.
alter table public.fantasy_league_members
  add column if not exists reset_position int;

-- Ein Spieler aus dem ersten Draft muss im Reset-Draft wieder wählbar sein.
alter table public.draft_picks
  drop constraint if exists draft_picks_league_id_player_id_key;
alter table public.draft_picks
  drop constraint if exists draft_picks_league_phase_player_key;
alter table public.draft_picks
  add constraint draft_picks_league_phase_player_key
  unique (league_id, phase, player_id);

-- Der feste Termin. Eine Funktion statt eines Literals an drei Stellen.
create or replace function public.fantasy_reset_termin(p_season int)
returns timestamptz
language sql immutable
as $$ select make_timestamptz(p_season, 12, 24, 0, 0, 0, 'Europe/Berlin') $$;

-- Steht die Liga gerade im Reset (geleert oder Reset-Draft läuft)?
create or replace function public.fantasy_im_reset(p_league_id uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select exists (select 1 from fantasy_leagues
                  where id = p_league_id
                    and (draft_status = 'reset'
                         or (draft_status = 'drafting' and draft_phase = 'reset')))
$$;

-- Die Einstellung lässt sich ändern, solange der Reset nicht stattgefunden
-- hat und der Termin nicht verstrichen ist.
create or replace function public.fantasy_reset_einstellung_pruefen()
returns trigger
language plpgsql
as $$
begin
  if new.reset_aktiv is distinct from old.reset_aktiv
     and (old.reset_erfolgt_at is not null
          or now() >= public.fantasy_reset_termin(old.season)) then
    raise exception 'Der Reset lässt sich nach dem 24.12. nicht mehr ändern';
  end if;
  return new;
end $$;

drop trigger if exists fantasy_leagues_reset_einstellung on public.fantasy_leagues;
create trigger fantasy_leagues_reset_einstellung
  before update of reset_aktiv on public.fantasy_leagues
  for each row execute function public.fantasy_reset_einstellung_pruefen();

-- Während des Resets kommt niemand außer über den Draft in einen Kader.
create or replace function public.fantasy_reset_sperre_kader()
returns trigger
language plpgsql security definer
set search_path to 'public'
as $$
begin
  if new.acquired_via <> 'draft' and public.fantasy_im_reset(new.league_id) then
    raise exception 'Während des Reset-Drafts sind keine Transfers möglich';
  end if;
  return new;
end $$;

drop trigger if exists fantasy_rosters_reset_sperre on public.fantasy_rosters;
create trigger fantasy_rosters_reset_sperre
  before insert on public.fantasy_rosters
  for each row execute function public.fantasy_reset_sperre_kader();

create or replace function public.fantasy_reset_sperre_antrag()
returns trigger
language plpgsql security definer
set search_path to 'public'
as $$
begin
  if public.fantasy_im_reset(new.league_id) then
    raise exception 'Während des Reset-Drafts sind keine Transfers möglich';
  end if;
  return new;
end $$;

drop trigger if exists fantasy_waiver_claims_reset_sperre on public.fantasy_waiver_claims;
create trigger fantasy_waiver_claims_reset_sperre
  before insert on public.fantasy_waiver_claims
  for each row execute function public.fantasy_reset_sperre_antrag();

-- Protokoll: Die Abgänge des Resets tragen `weg = 'reset'`. Sie bleiben im
-- Protokoll, damit der Rückblick auf die Hinrunde den Kader von damals
-- rekonstruieren kann (`kaderAm`); Transfers und Liga-Chat blenden sie aus.
create or replace function public.fantasy_bewegung_protokollieren()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if tg_op = 'INSERT' then
    insert into fantasy_roster_moves
      (league_id, manager_id, player_id, richtung, weg)
    values (new.league_id, new.manager_id, new.player_id, 'zugang',
            new.acquired_via);

  elsif tg_op = 'DELETE' then
    -- Die Liga selbst wird gerade gelöscht: kein Protokoll für eine Liga,
    -- die es nicht mehr gibt.
    if not exists (select 1 from fantasy_leagues where id = old.league_id) then
      return null;
    end if;
    insert into fantasy_roster_moves
      (league_id, manager_id, player_id, richtung, weg)
    values (old.league_id, old.manager_id, old.player_id, 'abgang',
            case when current_setting('matchup.reset', true) = '1'
                 then 'reset' end);

  elsif tg_op = 'UPDATE' and new.manager_id is distinct from old.manager_id then
    -- **Ein Trade ist zwei Bewegungen.** Er laeuft ueber ein `update` von
    -- `manager_id`, nicht ueber Delete+Insert; wer nur auf Delete hoert,
    -- sieht Trades gar nicht.
    insert into fantasy_roster_moves
      (league_id, manager_id, player_id, richtung, weg)
    values (old.league_id, old.manager_id, old.player_id, 'abgang', 'trade'),
           (new.league_id, new.manager_id, new.player_id, 'zugang', 'trade');
  end if;
  return null;
end$function$;

-- Der Reset selbst. Läuft nur einmal je Liga und nur, wenn alles passt.
create or replace function public.fantasy_reset_ausfuehren(p_league_id uuid)
returns boolean
language plpgsql security definer
set search_path to 'public'
as $$
declare l record;
begin
  select * into l from fantasy_leagues where id = p_league_id for update;
  if l.id is null or not l.reset_aktiv or l.reset_erfolgt_at is not null
     or l.draft_status <> 'done'
     or now() < public.fantasy_reset_termin(l.season) then
    return false;
  end if;

  update fantasy_trades set status = 'cancelled'
   where league_id = p_league_id
     and (status in ('pending', 'countered')
          or (status = 'accepted' and executed_at is null));
  update fantasy_waiver_claims set status = 'cancelled'
   where league_id = p_league_id and status = 'pending';
  delete from fantasy_waiver_players where league_id = p_league_id;
  delete from fantasy_draft_queue where league_id = p_league_id;

  perform set_config('matchup.reset', '1', true);
  delete from fantasy_rosters where league_id = p_league_id;
  perform set_config('matchup.reset', '0', true);

  update fantasy_leagues
     set draft_status = 'reset', draft_phase = 'reset', picks_made = 0,
         current_pick_deadline = null, draft_pausiert_rest = null,
         reset_erfolgt_at = now()
   where id = p_league_id;

  perform public.fantasy_post_system_message(p_league_id,
    '🔄 Reset zur Winterpause: Alle Kader sind geleert. Die Tabelle bleibt. '
    || 'Der Admin startet den Draft für die Rückrunde — der Tabellenletzte '
    || 'pickt zuerst.');
  return true;
end $$;

create or replace function public.fantasy_resets_faellig()
returns integer
language plpgsql security definer
set search_path to 'public'
as $$
declare r record; n int := 0;
begin
  for r in select id from fantasy_leagues
            where reset_aktiv and reset_erfolgt_at is null
              and draft_status = 'done'
              and now() >= public.fantasy_reset_termin(season) loop
    if public.fantasy_reset_ausfuehren(r.id) then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Der Admin startet den Reset-Draft. `p_reihenfolge` ist die Pick-Folge der
-- ersten Runde (Tabellenletzter zuerst), danach Snake wie immer.
create or replace function public.fantasy_reset_draft_starten(
  p_league_id uuid, p_reihenfolge uuid[])
returns void
language plpgsql security definer
set search_path to 'public'
as $$
declare v_created_by uuid; v_status text; v_secs int; v_n int;
begin
  select created_by, draft_status, draft_pick_seconds
    into v_created_by, v_status, v_secs
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Ersteller kann den Draft starten';
  end if;
  if v_status <> 'reset' then
    raise exception 'Die Liga wartet nicht auf einen Reset-Draft';
  end if;

  select count(*) into v_n from fantasy_league_members where league_id = p_league_id;
  if coalesce(array_length(p_reihenfolge, 1), 0) <> v_n
     or (select count(distinct x) from unnest(p_reihenfolge) x) <> v_n
     or exists (select 1 from unnest(p_reihenfolge) x
                 where x not in (select user_id from fantasy_league_members
                                  where league_id = p_league_id)) then
    raise exception 'Die Reihenfolge muss jeden Teilnehmer genau einmal enthalten';
  end if;

  update fantasy_league_members m
     set reset_position = arr.pos
    from (select uid, ord as pos
            from unnest(p_reihenfolge) with ordinality as t(uid, ord)) arr
   where m.league_id = p_league_id and m.user_id = arr.uid;

  update fantasy_leagues
     set draft_status = 'drafting', draft_phase = 'reset', picks_made = 0,
         draft_started_at = now(), draft_pausiert_rest = null,
         current_pick_deadline = now() + (v_secs || ' seconds')::interval
   where id = p_league_id;
end $$;

-- Wer am Zug ist: in der Reset-Phase nach `reset_position`, sonst wie bisher.
create or replace function public.fantasy_current_manager(p_league_id uuid)
 returns uuid
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_p int; v_n int; v_round0 int; v_pos int; v_slot int; v_manager uuid;
  v_phase text;
begin
  select picks_made, draft_phase into v_p, v_phase
    from fantasy_leagues where id = p_league_id;
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
  where league_id = p_league_id
    and (case when v_phase = 'reset' then reset_position
              else draft_position end) = v_slot;
  return v_manager;
end$function$;

revoke all on function public.fantasy_reset_ausfuehren(uuid) from public, anon, authenticated;
revoke all on function public.fantasy_resets_faellig() from public, anon, authenticated;
grant execute on function public.fantasy_reset_draft_starten(uuid, uuid[]) to authenticated;

-- Waiver-Frist: Ligen im Reset überspringen — dort gibt es nichts zu
-- vergeben, und der Vermerk soll nach dem Draft nicht für eine Runde fehlen,
-- die gar nicht abgerechnet wurde. Sonst wie 0141.
create or replace function public.fantasy_waivers_faellig()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare l record; v_runde int; n int := 0;
begin
  for l in select id, season from fantasy_leagues
            where not public.fantasy_im_reset(id) loop
    select f.round into v_runde
      from fixtures f
     where f.season = l.season and f.league_id = 'bundesliga'
       and f.id like 'sportmonks:%'
     group by f.round
    having public.fantasy_waiver_frist(l.season, f.round) <= now()
     order by f.round desc
     limit 1;
    continue when v_runde is null;
    continue when exists (select 1 from fantasy_waiver_laeufe
                          where league_id = l.id and round = v_runde);

    perform public.fantasy_process_waivers(l.id);
    insert into fantasy_waiver_laeufe (league_id, round) values (l.id, v_runde);
    perform public.fantasy_rueckblick_melden(l.id, v_runde);
    n := n + 1;
  end loop;
  return n;
end$function$;

select cron.schedule('fantasy-reset', '*/10 * * * *',
  $$ select public.fantasy_resets_faellig(); $$);
