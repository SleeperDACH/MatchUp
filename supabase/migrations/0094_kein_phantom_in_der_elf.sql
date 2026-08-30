-- Ein abgegebener Spieler muss aus der Aufstellung verschwinden.
--
-- Gemeldet als „der Waiver funktioniert nicht - man kann einen Spieler
-- aufnehmen und einen anderen droppen, das greift dann aber nicht, es
-- passiert ueberhaupt nichts".
--
-- **Gemessen in der laufenden Liga MatchUp! #1:** Zwei Manager hatten elf
-- Spieler in der Startelf, aber nur zehn davon im Kader — Eric mit Nadiem
-- Amiri, Majusch mit Serhou Guirassy. Beide Spieler waren abgegeben, standen
-- aber weiter in `fantasy_lineups.player_ids`.
--
-- Die Ursache: `player_ids` ist ein `text[]` ohne Fremdschluessel auf
-- `fantasy_rosters`. Ein Drop loescht die Kaderzeile und laesst das Array
-- unberuehrt. Die Wertung schneidet dann still die Menge:
-- `effectiveTotalsForRound` baut die Punkte **aus dem Kader** und
-- `chosenLineup` behaelt davon die aufgestellten — wer nicht mehr im Kader
-- ist, faellt heraus, ohne Ersatz und ohne Meldung. Der Manager spielt mit
-- zehn Mann und sieht es nirgends.
--
-- Das ist wieder dieselbe Sorte Fehler wie das leere Feld im Draft-Brett und
-- das stille Auto-Speichern: **Ein Zustand „hier fehlt jemand" sah aus wie
-- „hier ist alles in Ordnung".**
--
-- Behoben wird es mit einem **Trigger auf `fantasy_rosters`**, nicht in den
-- einzelnen Funktionen. Ein Spieler verlaesst einen Kader ueber
-- `fantasy_drop_player`, `fantasy_add_free_agent` (mit Abgang),
-- `fantasy_process_waivers`, `fantasy_trade_ausfuehren` und
-- `fantasy_admin_*` — fuenf Stellen sind fuenf Gelegenheiten, eine zu
-- vergessen, und der sechste Weg, den jemand naechstes Jahr baut, waere von
-- vornherein aussen vor. Dieselbe Begruendung wie beim Kaderlimit in 0083.
--
-- **Trades laufen ueber ein `update` von `manager_id`**, nicht ueber
-- Delete+Insert; der Trigger haengt deshalb an beidem und raeumt beim Update
-- die Aufstellung des **abgebenden** Managers.

-- ---------------------------------------------------------------------------
-- Welche Runde zaehlt gerade?
-- ---------------------------------------------------------------------------
-- Die niedrigste, die noch nicht vollstaendig abgepfiffen ist. **Dieselbe
-- Regel steht ein zweites Mal in Dart** (`aktiveRunde` in
-- `logic/aufstellungs_prognose.dart`) — bewusste Doppelung wie bei
-- `tip_scoring.dart` <-> SQL-View: Der Client braucht sie fuer die Anzeige,
-- die Datenbank fuer die Garantie. Wer eine aendert, aendert die andere mit.
create or replace function public.fantasy_laufende_runde(p_season int)
returns int
language sql
stable
as $$
  select min(round) from public.fixtures
   where season = p_season
     and league_id = 'bundesliga'
     and status <> 'finished';
$$;

-- Ist das Spiel dieses Spielers in der laufenden Runde schon angepfiffen?
create or replace function public.fantasy_spieler_laeuft(
  p_season int, p_player_id text)
returns boolean
language sql
stable
as $$
  select coalesce(
    public.fantasy_spieler_anpfiff(
      p_season, public.fantasy_laufende_runde(p_season), p_player_id) <= now(),
    false);
$$;

-- Steht der Spieler in der Elf der laufenden Runde?
create or replace function public.fantasy_steht_in_laufender_elf(
  p_league_id uuid, p_season int, p_player_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from fantasy_lineups
     where league_id = p_league_id
       and manager_id = auth.uid()
       and season = p_season
       and round = public.fantasy_laufende_runde(p_season)
       and p_player_id = any(player_ids));
$$;

-- ---------------------------------------------------------------------------
-- Der Trigger
-- ---------------------------------------------------------------------------
create or replace function public.fantasy_aus_aufstellung_entfernen()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_season int;
  v_runde  int;
  v_mgr    uuid;
begin
  -- Beim Update zaehlt der **alte** Manager: Er gibt den Spieler ab.
  v_mgr := old.manager_id;
  if tg_op = 'UPDATE' and new.manager_id = old.manager_id then
    return null;  -- kein Besitzerwechsel, nichts zu tun
  end if;

  select season into v_season from fantasy_leagues where id = old.league_id;
  if v_season is null then return null; end if;

  v_runde := public.fantasy_laufende_runde(v_season);
  if v_runde is null then return null; end if;  -- Saison durch

  -- **Nur die laufende und kommende Runden.** Vergangene Spieltage sind
  -- Geschichte; ihre Punkte sind gewertet, und eine nachtraeglich geaenderte
  -- Aufstellung waere eine Faelschung der Bilanz.
  update fantasy_lineups
     set player_ids = array_remove(player_ids, old.player_id),
         updated_at = now()
   where league_id = old.league_id
     and manager_id = v_mgr
     and round >= v_runde
     and old.player_id = any(player_ids);

  return null;
end$$;

drop trigger if exists fantasy_rosters_aufstellung_aufraeumen on public.fantasy_rosters;
create trigger fantasy_rosters_aufstellung_aufraeumen
  after delete or update of manager_id on public.fantasy_rosters
  for each row
  execute function public.fantasy_aus_aufstellung_entfernen();

-- ---------------------------------------------------------------------------
-- Angepfiffene Spieler sind nicht mehr frei holbar
-- ---------------------------------------------------------------------------
-- Der zweite Teil derselben Meldung: „Wenn das Spiel der jeweiligen Vereine
-- gestartet hat, muss bei den Free Agents das Waiver-Symbol kommen."
--
-- Der Grund ist nicht Kosmetik. Wer waehrend der Partie zusieht und dann den
-- Spieler holt, der gerade getroffen hat, wertet mit Wissen, das beim
-- Aufstellen niemand hatte. Und selbst gutglaeubig bringt es nichts: Die
-- Aufstellung ist fuer ihn ohnehin gesperrt (0084), er kaeme diesen Spieltag
-- gar nicht in die Elf. Ein Knopf, der etwas Sinnloses tut, ist schlimmer als
-- keiner — genau das war die Beschwerde.
--
-- Frei wird er wieder, sobald der Spieltag abgepfiffen ist: Dann ist die
-- laufende Runde die naechste, und deren Anpfiff liegt in der Zukunft.
create or replace function public.fantasy_add_free_agent(
  p_league_id uuid, p_add_player_id text, p_drop_player_id text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_season int; v_roster jsonb; v_locked boolean; v_count int; v_msg text;
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
  if exists (select 1 from fantasy_waiver_players
             where league_id = p_league_id and player_id = p_add_player_id
               and clears_at > now()) then
    raise exception 'Spieler ist auf dem Waiver – bitte per Antrag holen';
  end if;

  -- NEU: sein Spiel laeuft schon.
  if public.fantasy_spieler_laeuft(v_season, p_add_player_id) then
    raise exception 'Sein Spiel läuft bereits – er ist erst nach dem Spieltag wieder holbar';
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

  v_msg := '✅ ' || public._fantasy_username(auth.uid()) || ' hat '
    || public._fantasy_playername(p_add_player_id) || ' verpflichtet';
  if p_drop_player_id is not null then
    v_msg := v_msg || ' und ' || public._fantasy_playername(p_drop_player_id)
      || ' abgegeben';
  end if;
  perform public.fantasy_post_system_message(p_league_id, v_msg || '.');
end$function$;

create or replace function public.fantasy_drop_player(
  p_league_id uuid, p_player_id text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_season int;
begin
  if not exists (select 1 from fantasy_rosters
                 where league_id = p_league_id and player_id = p_player_id
                   and manager_id = auth.uid()) then
    raise exception 'Spieler ist nicht in deinem Kader';
  end if;

  select season into v_season from fantasy_leagues where id = p_league_id;
  if public.fantasy_steht_in_laufender_elf(p_league_id, v_season, p_player_id)
     and public.fantasy_spieler_laeuft(v_season, p_player_id) then
    raise exception 'Er steht in deiner Elf und sein Spiel läuft schon – erst nach dem Spieltag abzugeben';
  end if;

  delete from fantasy_rosters
    where league_id = p_league_id and player_id = p_player_id
      and manager_id = auth.uid();
  perform public.fantasy_put_on_wire(p_league_id, p_player_id);
  perform public.fantasy_post_system_message(p_league_id,
    '🔻 ' || public._fantasy_username(auth.uid()) || ' hat '
      || public._fantasy_playername(p_player_id) || ' abgegeben.');
end$function$;

-- ---------------------------------------------------------------------------
-- Einmalig: die Phantome aus der laufenden und den kommenden Runden raeumen
-- ---------------------------------------------------------------------------
-- Abgepfiffene Spieltage bleiben unberuehrt — ihre Bilanz ist gewertet, und
-- eine nachtraeglich geaenderte Aufstellung waere eine Faelschung.
--
-- An der Punktzahl aendert das nichts (die Wertung bildet die Punkte ohnehin
-- ueber den Kader), aber solange das Phantom dasteht, sieht die Elf im Editor
-- voll aus, obwohl ein Platz leer ist — und niemand fuellt einen Platz, von
-- dem er nicht weiss.
update public.fantasy_lineups fl
   set player_ids = (
         select coalesce(array_agg(x), '{}')
           from unnest(fl.player_ids) as x
          where exists (select 1 from public.fantasy_rosters r
                        where r.league_id = fl.league_id
                          and r.player_id = x
                          and r.manager_id = fl.manager_id)),
       updated_at = now()
  from public.fantasy_leagues l
 where l.id = fl.league_id
   and fl.round >= coalesce(public.fantasy_laufende_runde(l.season), 999)
   and exists (
     select 1 from unnest(fl.player_ids) as x
      where not exists (select 1 from public.fantasy_rosters r
                        where r.league_id = fl.league_id
                          and r.player_id = x
                          and r.manager_id = fl.manager_id));
