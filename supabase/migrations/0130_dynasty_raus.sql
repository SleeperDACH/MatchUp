-- **Dynasty ist raus** (Ansage vom 27.09.2026).
--
-- Der Modus kannte zwei Dinge, die es sonst nirgends gibt: den U20-Draft als
-- zweite Draft-Phase und den Saison-Rollover, der den Kader über Jahre
-- weiterträgt. Beides fällt weg, und damit auch die Reservierung von Rookies
-- für einen zweiten Draft, den niemand mehr startet.
--
-- **Die Spalten bleiben stehen** (`fantasy_leagues.mode`, `.draft_phase`,
-- `.u20_rounds`, `.u20_draft_pending`, `draft_picks.phase`). Der Grund ist
-- `phase`: Sie steckt im Primärschlüssel von `draft_picks`, und den auf einer
-- Tabelle mit Hunderten Picks umzubauen wäre eine riskante Migration ohne
-- jeden Gewinn — der Client liest die Spalten schlicht nicht mehr. Wer sie
-- später doch entfernt, muss den Realtime-Stream in `draft_repository.dart`
-- mitziehen: Ohne `phase` im Schlüssel hielte Supabase verschiedene Zeilen für
-- dieselbe (der Fehler ist hier schon einmal aufgetreten).
--
-- **Reihenfolge ist wichtig:** Erst die beiden Aufrufer neu schreiben, dann
-- die gerufene Funktion entfernen. Andersherum stünde `fantasy_add_free_agent`
-- zwischendurch mit einem Aufruf ins Leere da — und das ist der Weg, über den
-- jeder Spieler geholt wird.
--
-- Die Rümpfe sind aus der laufenden Datenbank gezogen (`pg_get_functiondef`)
-- und nur um den U20-Block gekürzt; sie aus fünf Migrationen
-- zusammenzusuchen wäre ein Rückschritt, jede davon hat sie seither angefasst.

-- 1) Free Agency ohne die U20-Sperre.
create or replace function public.fantasy_add_free_agent(
  p_league_id uuid, p_add_player_id text, p_drop_player_id text default null::text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_season int; v_roster jsonb; v_count int;
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

  -- Die U20-Reservierung ist hier entfallen: Sie galt nur in Dynasty.

  if p_drop_player_id is not null then
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and player_id = p_drop_player_id
                     and manager_id = auth.uid()) then
      raise exception 'Abzugebender Spieler ist nicht in deinem Kader';
    end if;
    -- **Kein Riegel mehr fuer die laufende Elf.** Hat sein Verein angepfiffen,
    -- bleibt er fuer diesen Spieltag in der Elf und punktet dort weiter
    -- (Trigger aus 0115); der Tausch kostet ihn nur den Kaderplatz.
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

end$function$;

-- 2) Waiver-Antrag ohne die U20-Sperre.
create or replace function public.fantasy_submit_waiver_claim(
  p_league_id uuid, p_add_player_id text, p_drop_player_id text default null::text,
  p_rank integer default 1)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_season int; v_id uuid;
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

  -- Die U20-Reservierung ist hier entfallen: Sie galt nur in Dynasty.

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
end$function$;

-- 3) Jetzt erst die U20-Funktionen entfernen — nach den Aufrufern.
--
-- `fantasy_is_locked` wird nachgemessen von **nur** `fantasy_u20_gesperrt`
-- gerufen (Abfrage über `pg_proc.prosrc` am 27.09.2026), fällt also mit.
drop function if exists public.fantasy_u20_gesperrt(uuid, text);
drop function if exists public.fantasy_is_locked(date, boolean, integer, timestamptz);

-- 4) Der U20-Draft und der Saison-Rollover: beide gab es nur für Dynasty.
drop function if exists public.start_u20_draft(uuid);
drop function if exists public.fantasy_rollover_season(uuid);

-- 5) Keine Liga darf mehr im Dynasty-Modus stehen.
--
-- Die eine, die es gab („DynastyTest", Draft nie gestartet), ist am
-- 27.09.2026 auf Ansage gelöscht worden. Der Check hält fest, dass hier keine
-- neue entstehen kann — sonst läge morgen wieder eine Zeile da, deren Modus
-- die App nicht kennt.
update fantasy_leagues set mode = 'liga' where mode <> 'liga';

alter table fantasy_leagues
  drop constraint if exists fantasy_leagues_mode_check;
alter table fantasy_leagues
  add constraint fantasy_leagues_mode_check check (mode = 'liga');
