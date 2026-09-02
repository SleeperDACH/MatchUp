-- Wer die Bundesliga verlaesst, verlaesst auch den Fantasy-Pool.
--
-- Bisher endete ein Abgang in `fantasy_prune_departed_players` (0073) an der
-- eigenen Vorsichtsregel: Geloescht wurde nur, wer in **keiner**
-- referenzierenden Tabelle stand. Wer gedraftet, gerostert oder auch nur
-- einmal gewertet worden war, blieb im Pool stehen — mit seinem alten
-- Bundesliga-Verein an der Karte, holbar in der Free Agency, waehlbar im
-- Draft, und im Kader seines Managers auf einem Platz, auf dem er bis zum
-- Saisonende **null Punkte** bringt.
--
-- Das ist die schlechtere Haelfte beider Welten: Der Schutz galt dem
-- Manager, kostete ihn aber genau den Kaderplatz, den er braucht.
--
-- Drei Teile:
--
-- 1. **Eine Markierung statt eines Loeschens.** `players.abgang_am` haelt
--    fest, wann der Kader-Sync den Spieler in keinem der 18 Kader mehr fand.
--    Loeschen bleibt, wo es geht (niemand verweist auf ihn); wo Fremd-
--    schluessel es verbieten — Draft-Picks, Stats, alte Trades — bleibt die
--    Zeile stehen und traegt die Markierung. **Das ist Absicht:** Die
--    Wertung der gespielten Spieltage haengt an `player_match_stats`, und
--    das Draft-Brett soll auch im Mai noch zeigen, wer wen gezogen hat. Ein
--    Name, den niemand mehr aufloesen kann, waere ein Ruecktritt hinter
--    beides.
-- 2. **Raus aus den Kadern.** Die Kaderzeile wird geloescht; die Trigger aus
--    0094 und 0096 raeumen die Aufstellung und protokollieren den Abgang.
--    Der Weg heisst `abgewandert` — die Anzeige macht daraus „Bundesliga
--    verlassen", damit niemand einen Drop des Managers darin sieht.
--    **Nicht angetastet wird, wer in der Elf der laufenden Runde steht:**
--    Der Trigger aus 0094 raeumt ab der laufenden Runde, und wer am Samstag
--    noch gepunktet hat, verlaere diese Punkte am Montag rueckwirkend. Er
--    faellt dann beim naechsten naechtlichen Lauf, wenn der Spieltag durch
--    ist.
-- 3. **Nicht wieder rein.** Ein `before insert`-Trigger auf
--    `fantasy_rosters` weist einen Abgewanderten ab — an einer Stelle statt
--    in den sechs Funktionen, ueber die jemand in einen Kader kommt
--    (Draft, Free Agency, Waiver, Trade, Autopick, Admin). Dieselbe
--    Begruendung wie beim Kaderlimit (0083) und beim Aufstellungs-
--    Aufraeumen (0094).
--
-- Offene Vorgaenge, die ins Leere liefen, werden mit aufgeraeumt: Wunsch-
-- listen, Waiver-Wire, Antraege und schwebende Trade-Angebote.
--
-- **Rueckkehrer gibt es.** Wer im Winter zurueckkommt, steht wieder in einem
-- Kader-Abruf; dann faellt `abgang_am` zurueck auf NULL und er ist normal
-- holbar. Eine Markierung, die nur in eine Richtung geht, waere eine Falle.

-- ---------------------------------------------------------------------------
-- 1. Die Markierung
-- ---------------------------------------------------------------------------
alter table public.players
  add column if not exists abgang_am timestamptz;

comment on column public.players.abgang_am is
  'Wann der Kader-Sync (sync-squads) den Spieler in keinem Bundesliga-Kader '
  'mehr fand. NULL = im Pool. Gesetzt und zurueckgenommen ausschliesslich von '
  'fantasy_prune_departed_players.';

-- Der Pool wird bei jedem App-Start ganz gelesen; die Markierung filtert die
-- Anzeige, nicht die Abfrage. Ein Teilindex kostet nichts und hilft den
-- Aufraeum-Abfragen unten.
create index if not exists players_abgang_idx
  on public.players (abgang_am) where abgang_am is not null;

-- ---------------------------------------------------------------------------
-- 3. Nicht wieder rein (steht vor dem Aufraeumen, weil das Aufraeumen ihn
--    schon voraussetzt)
-- ---------------------------------------------------------------------------
create or replace function public.fantasy_kein_abgewanderter()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if exists (select 1 from players
              where id = new.player_id and abgang_am is not null) then
    raise exception 'Spieler hat die Bundesliga verlassen';
  end if;
  return new;
end$$;

drop trigger if exists fantasy_rosters_kein_abgewanderter on public.fantasy_rosters;
create trigger fantasy_rosters_kein_abgewanderter
  before insert on public.fantasy_rosters
  for each row
  execute function public.fantasy_kein_abgewanderter();

-- ---------------------------------------------------------------------------
-- 2. Der Lauf selbst
-- ---------------------------------------------------------------------------
-- Rueckgabe waechst um zwei Zaehler; deshalb erst weg, dann neu.
drop function if exists public.fantasy_prune_departed_players(text[], text[]);

create function public.fantasy_prune_departed_players(
  p_current_ids text[], p_bl_clubs text[])
returns table(deleted int, kept int, abgewandert int, aus_kadern int)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  -- **`now()`, nicht `clock_timestamp()`.** Der Protokoll-Trigger schreibt
  -- `passiert_am` mit dem Default `now()` — dem Zeitpunkt des Transaktions-
  -- beginns. Der liegt VOR jedem `clock_timestamp()` innerhalb der Funktion;
  -- ein Vergleich `passiert_am >= clock_timestamp()` traefe deshalb keine
  -- einzige der Zeilen, die diese Funktion gerade selbst erzeugt hat.
  v_start timestamptz := now();
  v_ids   text[];
  v_trade record;
  v_namen text;
begin
  -- Rueckkehrer zuerst: Wer wieder in einem Kader steht, ist wieder da.
  update public.players set abgang_am = null
   where abgang_am is not null
     and id = any(p_current_ids);

  -- Abgaenge markieren. `abgang_am` bleibt beim ersten Lauf stehen, in dem er
  -- fehlte — das Datum soll den Wechsel datieren, nicht den letzten Sync.
  update public.players set abgang_am = now()
   where id like 'sportmonks:%'
     and club = any(p_bl_clubs)
     and not (id = any(p_current_ids))
     and abgang_am is null;

  select coalesce(array_agg(id), '{}') into v_ids
    from public.players
   where abgang_am is not null
     and id like 'sportmonks:%'
     and club = any(p_bl_clubs)
     and not (id = any(p_current_ids));

  if coalesce(array_length(v_ids, 1), 0) = 0 then
    deleted := 0; kept := 0; abgewandert := 0; aus_kadern := 0;
    return next;
    return;
  end if;

  -- Wunschlisten: harmlos, und sie wuerden sonst als Referenz gelten.
  delete from public.fantasy_draft_queue where player_id = any(v_ids);

  -- Waiver-Wire: ein Abgewanderter liegt dort umsonst.
  delete from public.fantasy_waiver_players where player_id = any(v_ids);

  -- Ein Antrag auf einen Abgewanderten ist gegenstandslos. `invalid` ist der
  -- vorgesehene Ausgang dafuer (0007), samt Grund in Klartext.
  update public.fantasy_waiver_claims
     set status = 'invalid',
         reason = 'Spieler hat die Bundesliga verlassen',
         processed_at = now()
   where status = 'pending'
     and add_player_id = any(v_ids);

  -- Wer einen Abgewanderten abgeben wollte, muss nichts mehr abgeben: Der
  -- Platz wird unten ohnehin frei. Der Antrag bleibt, nur ohne Gegenseite.
  update public.fantasy_waiver_claims
     set drop_player_id = null
   where status = 'pending'
     and drop_player_id = any(v_ids);

  -- Schwebende Trade-Angebote mit einem Abgewanderten darin. Sie zu lassen
  -- hiesse, ein Angebot anzubieten, das beim Annehmen scheitert.
  --
  -- **Hier bleibt eine Chat-Meldung**, obwohl 0106 die Kaderbewegungen aus
  -- dem Chat genommen hat: Sie meldet nicht, was geschehen ist, sondern dass
  -- etwas Erwartetes **nicht** geschieht — dieselbe Ausnahme wie beim
  -- hinfaelligen Trade in `fantasy_trade_ausfuehren`.
  for v_trade in
    select t.id, t.league_id,
           string_agg(distinct public._fantasy_playername(i.player_id), ', ')
             as namen
      from public.fantasy_trades t
      join public.fantasy_trade_items i on i.trade_id = t.id
     where t.status = 'pending'
       and i.player_id = any(v_ids)
     group by t.id, t.league_id
  loop
    update public.fantasy_trades
       set status = 'cancelled', resolved_at = now()
     where id = v_trade.id;
    v_namen := v_trade.namen;
    perform public.fantasy_post_system_message(
      v_trade.league_id,
      '⚠️ Ein Trade-Angebot wurde zurückgezogen: ' || v_namen
        || ' hat die Bundesliga verlassen.');
  end loop;

  -- Raus aus den Kadern — ausser aus einer Elf, die gerade gewertet wird.
  with weg as (
    delete from public.fantasy_rosters r
     using public.fantasy_leagues l
     where l.id = r.league_id
       and r.player_id = any(v_ids)
       and not exists (
         select 1 from public.fantasy_lineups f
          where f.league_id = r.league_id
            and f.manager_id = r.manager_id
            and f.season = l.season
            and f.round = public.fantasy_laufende_runde(l.season)
            and r.player_id = any(f.player_ids))
    returning r.player_id)
  select count(*) into aus_kadern from weg;

  -- Der Protokoll-Trigger (0096) traegt beim Loeschen keinen Weg ein — er
  -- kann Drop, Waiver-Abgabe und Admin-Korrektur nicht unterscheiden. Hier
  -- ist er bekannt, also steht er auch da.
  update public.fantasy_roster_moves
     set weg = 'abgewandert'
   where richtung = 'abgang'
     and weg is null
     and player_id = any(v_ids)
     and passiert_am >= v_start;

  -- Und die, auf die jetzt nichts mehr zeigt, ganz raus.
  with del as (
    delete from public.players p
    where p.id = any(v_ids)
      and not exists (select 1 from public.draft_picks x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_rosters x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_trade_items x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_waiver_players x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_waiver_claims x
                        where x.add_player_id = p.id or x.drop_player_id = p.id)
      and not exists (select 1 from public.player_match_stats x where x.player_id = p.id)
    returning p.id)
  select count(*) into deleted from del;

  abgewandert := array_length(v_ids, 1);
  kept := abgewandert - deleted;
  return next;
end$$;

revoke all on function public.fantasy_prune_departed_players(text[], text[])
  from public, anon, authenticated;
grant execute on function public.fantasy_prune_departed_players(text[], text[])
  to service_role;
