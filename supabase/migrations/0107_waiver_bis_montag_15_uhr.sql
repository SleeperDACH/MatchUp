-- Der Waiver bekommt eine Frist: Montag 15:00, in englischen Wochen
-- Donnerstag 15:00. Und der Spielplan zaehlt nur noch aus einer Quelle.
--
-- Zwei Befunde aus der Produktion stehen dahinter.
--
-- **Erstens: `fixtures` traegt die Bundesliga-Saison doppelt.** 306 Zeilen von
-- OpenLigaDB und 306 von Sportmonks. Seit der Umstellung holt `sync-fixtures`
-- OpenLigaDB nur noch fuer die WM (`OL_LEAGUES` enthaelt bloss `wm2026`) — die
-- Bundesliga-Zeilen sind Altbestand und stehen deshalb alle auf `scheduled`,
-- fuer immer. `fantasy_laufende_runde` ist „die niedrigste nicht beendete
-- Runde" und lieferte darum **1 statt 2**. Folge: 231 von 232 freien Spielern
-- galten als „Spiel laeuft", niemand war direkt holbar, und jeder Zugang wurde
-- zum Antrag.
--
-- Die Zeilen fallen weg (nichts verweist darauf: `tips`, `fixture_odds`,
-- `predicted_lineups` und `predicted_formations` tragen fuer die Bundesliga
-- ausschliesslich Sportmonks-IDs; die 98 OpenLigaDB-Quoten gehoeren zur WM und
-- bleiben unberuehrt). Zusaetzlich filtern die Runden-Funktionen jetzt auf
-- `sportmonks:` — ein Altbestand darf die Rechnung nie wieder kippen.
--
-- **Zweitens: Antraege auf laufende Spieler wurden nie abgearbeitet.** Der
-- einzige Cron rief `fantasy_process_due_waivers`, und die laeuft ueber
-- `fantasy_waiver_players` — also nur ueber ausdruecklich gedroppte Spieler.
-- Ein Antrag auf einen freien Spieler, dessen Partie lief, steht dort nicht
-- drin und blieb ewig `pending` (zwei solche Antraege hingen seit dem 30.08.).
--
-- **Die neue Regel**, wie sie gewuenscht wurde:
--
--   * Ein Spieler liegt **ab dem Anpfiff seines Vereins** auf dem Waiver —
--     nicht ab dem ersten Anpfiff des Spieltags. Wer Sonntag spielt, ist bis
--     Sonntag 15:30 direkt zu holen.
--   * Der Waiver laeuft bis **Montag 15:00** (Europe/Berlin). Dann werden alle
--     Antraege in Prioritaetsreihenfolge abgearbeitet.
--   * **Englische Woche** (Spiele am Dienstag *und* Mittwoch): Donnerstag
--     15:00.
--   * Wer **ausserhalb** eines Waiver-Fensters gedroppt wird, liegt 24 Stunden
--     auf dem Wire — die bisherige Regel, unveraendert.
--
-- Zwischen Frist und naechstem Anpfiff gilt damit wieder „first come, first
-- served": Wer frei ist, wird direkt geholt.

-- ---------------------------------------------------------------------------
-- 1. Der Altbestand
-- ---------------------------------------------------------------------------
delete from public.fixtures
 where league_id = 'bundesliga'
   and id like 'openligadb:%';

-- ---------------------------------------------------------------------------
-- 2. Nur noch Sportmonks
-- ---------------------------------------------------------------------------
create or replace function public.fantasy_laufende_runde(p_season int)
returns int language sql stable security definer set search_path to 'public' as $$
  select min(round) from public.fixtures
   where season = p_season
     and league_id = 'bundesliga'
     and id like 'sportmonks:%'
     and status <> 'finished';
$$;

create or replace function public.fantasy_spieler_anpfiff(
  p_season int, p_round int, p_player_id text)
returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select min(f.kickoff)
    from players p
    join fixtures f
      on f.season = p_season and f.round = p_round
     and f.league_id = 'bundesliga'
     and f.id like 'sportmonks:%'
     and (f.home_name = p.club or f.away_name = p.club)
   where p.id = p_player_id;
$$;

-- ---------------------------------------------------------------------------
-- 3. Die Frist
-- ---------------------------------------------------------------------------

-- Der naechste Wochentag um 15:00 Ortszeit **echt nach** `p_ab`.
--
-- Gerechnet wird in Europe/Berlin, nicht in UTC: „Montag 15 Uhr" ist eine
-- Uhrzeit fuer Menschen, und sie darf im Winter nicht auf 16 Uhr rutschen.
create or replace function public.fantasy_naechste_frist(
  p_ab timestamptz, p_isodow int)
returns timestamptz language sql immutable as $$
  select min(ts) from (
    select (((p_ab at time zone 'Europe/Berlin')::date + d)::timestamp
              + time '15:00') at time zone 'Europe/Berlin' as ts,
           extract(isodow from ((p_ab at time zone 'Europe/Berlin')::date + d))
             as dow
      from generate_series(0, 7) as d
  ) k
  where k.dow = p_isodow and k.ts > p_ab;
$$;

-- Wann endet der Waiver dieser Runde?
--
-- Massgeblich ist der **letzte** Anpfiff der Runde, nicht der erste: Der
-- Waiver soll erst schliessen, wenn alle gespielt haben. Liegen Spiele am
-- Dienstag *und* Mittwoch, ist es eine englische Woche — dann Donnerstag.
create or replace function public.fantasy_waiver_frist(p_season int, p_round int)
returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select case
           when s.letzter is null then null
           else public.fantasy_naechste_frist(
                  s.letzter, case when s.di and s.mi then 4 else 1 end)
         end
    from (
      select max(f.kickoff) as letzter,
             bool_or(extract(isodow from f.kickoff at time zone 'Europe/Berlin') = 2) as di,
             bool_or(extract(isodow from f.kickoff at time zone 'Europe/Berlin') = 3) as mi
        from public.fixtures f
       where f.season = p_season and f.league_id = 'bundesliga'
         and f.id like 'sportmonks:%' and f.round = p_round
    ) s;
$$;

-- Die Runde, deren Waiver gerade offen ist: erster Anpfiff vorbei, Frist noch
-- nicht erreicht. `null` heisst „freie Phase" — direkt holen.
create or replace function public.fantasy_wire_runde(
  p_season int, p_at timestamptz default now())
returns int language sql stable security definer set search_path to 'public' as $$
  select f.round
    from public.fixtures f
   where f.season = p_season and f.league_id = 'bundesliga'
     and f.id like 'sportmonks:%'
   group by f.round
  having min(f.kickoff) <= p_at
     and public.fantasy_waiver_frist(p_season, f.round) > p_at
   order by f.round desc
   limit 1;
$$;

-- Liegt dieser Spieler gerade auf dem Waiver?
--
-- Zwei Wege fuehren dahin, und sie sind verschieden:
--   * **ausdruecklich gedroppt** — steht mit `clears_at` in
--     `fantasy_waiver_players` (ausserhalb des Fensters 24 Stunden lang);
--   * **sein Verein hat angepfiffen** und die Frist ist noch nicht erreicht.
create or replace function public.fantasy_auf_dem_wire(
  p_league_id uuid, p_season int, p_player_id text,
  p_at timestamptz default now())
returns boolean language plpgsql stable security definer set search_path to 'public' as $$
declare v_runde int;
begin
  if exists (select 1 from fantasy_waiver_players
             where league_id = p_league_id and player_id = p_player_id
               and clears_at > p_at) then
    return true;
  end if;
  v_runde := public.fantasy_wire_runde(p_season, p_at);
  if v_runde is null then return false; end if;
  return coalesce(
    public.fantasy_spieler_anpfiff(p_season, v_runde, p_player_id) <= p_at,
    false);
end$$;

-- Naechste Frist fuer die Anzeige: Runde und Zeitpunkt.
--
-- Der Rueckgabetyp aendert sich (die alte Fassung hiess die Spalte anders),
-- deshalb muss die Funktion erst weg — `create or replace` kann das nicht.
drop function if exists public.fantasy_next_waiver_window(int);

create or replace function public.fantasy_next_waiver_window(p_season int)
returns table(round int, deadline timestamptz)
language sql stable security definer set search_path to 'public' as $$
  select f.round, public.fantasy_waiver_frist(p_season, f.round) as deadline
    from public.fixtures f
   where f.season = p_season and f.league_id = 'bundesliga'
     and f.id like 'sportmonks:%'
   group by f.round
  having public.fantasy_waiver_frist(p_season, f.round) > now()
   order by 2
   limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 4. Ein Drop legt auf den Wire — bis zur Frist, sonst 24 Stunden
-- ---------------------------------------------------------------------------
create or replace function public.fantasy_put_on_wire(
  p_league_id uuid, p_player_id text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_season int; v_runde int; v_bis timestamptz;
begin
  select season into v_season from fantasy_leagues where id = p_league_id;
  v_runde := public.fantasy_wire_runde(v_season);
  -- Im laufenden Fenster endet der Wire **mit der Frist**, nicht 24 Stunden
  -- spaeter: Sonst faellt ein Samstag-Drop am Sonntag mitten im Spieltag frei.
  v_bis := coalesce(public.fantasy_waiver_frist(v_season, v_runde),
                    now() + interval '24 hours');
  insert into fantasy_waiver_players (league_id, player_id, clears_at)
  values (p_league_id, p_player_id, v_bis)
  on conflict (league_id, player_id) do update set clears_at = excluded.clears_at;
end$$;
-- ---------------------------------------------------------------------------
-- 5. Holen und Beantragen fragen dieselbe Stelle
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fantasy_add_free_agent(p_league_id uuid, p_add_player_id text, p_drop_player_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- **Ein Riegel statt zweier.** Vorher standen hier die 24-Stunden-Sperre und
  -- „sein Spiel laeuft" nebeneinander; jetzt beantwortet
  -- `fantasy_auf_dem_wire` beides — samt der Frist, die den Waiver eines
  -- Spieltags bis Montag 15:00 offen haelt.
  if public.fantasy_auf_dem_wire(p_league_id, v_season, p_add_player_id) then
    raise exception 'Er liegt auf dem Waiver – bitte per Antrag holen';
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
    -- NEU: Wer in der Elf steht und schon spielt, darf nicht raus — das waere
    -- eine nachtraegliche Aenderung an einem laufenden Spieltag. Auf der Bank
    -- ist er dagegen frei abzugeben, dort haengt nichts daran.
    if public.fantasy_steht_in_laufender_elf(p_league_id, v_season, p_drop_player_id)
       and public.fantasy_spieler_laeuft(v_season, p_drop_player_id) then
      raise exception 'Er steht in deiner Elf und sein Spiel läuft schon – erst nach dem Spieltag abzugeben';
    end if;
    delete from fantasy_rosters
      where league_id = p_league_id and player_id = p_drop_player_id
        and manager_id = auth.uid();
    perform public.fantasy_put_on_wire(p_league_id, p_drop_player_id);
  end if;

  select count(*) into v_count from fantasy_rosters
    where league_id = p_league_id and manager_id = auth.uid();
  if v_count >= public.fantasy_squad_size(v_roster) then
    raise exception 'Kader voll – du musst einen Spieler abgeben';
  end if;

  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
  values (p_league_id, auth.uid(), p_add_player_id, 'fa');

end$function$
;
CREATE OR REPLACE FUNCTION public.fantasy_submit_waiver_claim(p_league_id uuid, p_add_player_id text, p_drop_player_id text DEFAULT NULL::text, p_rank integer DEFAULT 1)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_season int; v_locked boolean; v_id uuid;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  select season into v_season from fantasy_leagues where id = p_league_id;

  -- Beantragbar ist, wer auf dem Waiver liegt: ausdruecklich gedroppt oder
  -- sein Verein hat angepfiffen und die Frist ist noch nicht erreicht. Wer
  -- frei und abholbar ist, braucht keinen Antrag — den nimmt man einfach.
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_add_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;
  if not public.fantasy_auf_dem_wire(p_league_id, v_season, p_add_player_id) then
    raise exception 'Spieler ist frei – du kannst ihn direkt holen';
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
end$function$

;

-- ---------------------------------------------------------------------------
-- 6. Zur Frist werden die Antraege abgearbeitet
-- ---------------------------------------------------------------------------
--
-- **Ein Protokoll statt eines Zeitplans.** Der Cron koennte um 15:00 laufen —
-- aber pg_cron rechnet in UTC, und „Montag 15 Uhr" waere damit im Winter
-- 14 Uhr. Ausserdem faellt ein Lauf aus, wenn die Datenbank in genau dieser
-- Minute nicht kann. Deshalb schaut ein Lauf alle fuenf Minuten nach, **ob
-- eine Frist verstrichen ist, fuer die noch nicht abgerechnet wurde** — das
-- holt einen verpassten Termin von selbst nach.
create table if not exists public.fantasy_waiver_laeufe (
  league_id   uuid        not null references public.fantasy_leagues(id) on delete cascade,
  round       int         not null,
  erledigt_am timestamptz not null default now(),
  primary key (league_id, round)
);

alter table public.fantasy_waiver_laeufe enable row level security;
drop policy if exists "Waiver-Laeufe der eigenen Liga lesen"
  on public.fantasy_waiver_laeufe;
create policy "Waiver-Laeufe der eigenen Liga lesen"
  on public.fantasy_waiver_laeufe for select
  to authenticated
  using (public.is_fantasy_member(league_id));

create or replace function public.fantasy_waivers_faellig()
returns int language plpgsql security definer set search_path to 'public' as $$
declare l record; v_runde int; n int := 0;
begin
  for l in select id, season from fantasy_leagues loop
    -- Die juengste Runde, deren Frist bereits verstrichen ist.
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
    n := n + 1;
  end loop;
  return n;
end$$;

-- Zweimal anlegen waere ein Fehler, also erst abbestellen, wenn es den Auftrag
-- schon gibt.
select cron.unschedule('fantasy-waiver-frist')
 where exists (select 1 from cron.job where jobname = 'fantasy-waiver-frist');

select cron.schedule('fantasy-waiver-frist', '*/5 * * * *',
                     $$ select public.fantasy_waivers_faellig(); $$);
