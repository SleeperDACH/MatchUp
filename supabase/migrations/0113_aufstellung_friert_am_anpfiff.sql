-- Eine angepfiffene Aufstellung wird nicht mehr angefasst.
--
-- Gemeldet: „Wenn man einen Spieler, der am Wochenende in der Startelf stand,
-- droppt, beeinflusst das im Nachhinein die Punkte. Das darf auf keinen Fall
-- passieren. Der Kader bleibt, sobald das Spiel startet, gelocked."
--
-- **Die Ursache war eine Zeile, die ich selbst geschrieben habe.** Der Trigger
-- aus 0094 raeumt einen abgegebenen Spieler aus den Aufstellungen — mit dem
-- Filter `round >= fantasy_laufende_runde(...)` und dem Kommentar „nur die
-- laufende und kommende Runden; vergangene Spieltage sind Geschichte".
--
-- Genau das war der Denkfehler: **Die laufende Runde ist die, die gerade
-- gewertet wird.** Ihre Elf ist keine Planung mehr, sondern eine Wette, die
-- laeuft. Sie zu aendern verschiebt Punkte rueckwirkend.
--
-- Dasselbe galt fuer das einmalige Aufraeumen in 0094 (Zeile 266): Es lief am
-- 30.08. um 09:15 mitten in Spieltag 1 und hat drei Aufstellungen beschnitten.
--
-- Neu: Angefasst wird nur, was **noch nicht angepfiffen** ist.

create or replace function public.fantasy_runde_angepfiffen(
  p_season int, p_round int, p_at timestamptz default now())
returns boolean language sql stable security definer set search_path to 'public' as $$
  -- Der **erste** Anpfiff der Runde schliesst sie ab. Nicht der des einzelnen
  -- Vereins: Ab dem Moment laeuft die Wertung, und wer danach noch an seiner
  -- Elf dreht, dreht an einer laufenden Bilanz. Fuer den einzelnen Spieler
  -- gilt zusaetzlich die feinere Sperre aus 0084.
  select coalesce(min(f.kickoff) <= p_at, false)
    from public.fixtures f
   where f.season = p_season and f.league_id = 'bundesliga'
     and f.id like 'sportmonks:%' and f.round = p_round;
$$;

create or replace function public.fantasy_aus_aufstellung_entfernen()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare
  v_season int;
  v_mgr    uuid;
begin
  -- Beim Update zaehlt der **alte** Manager: Er gibt den Spieler ab.
  v_mgr := old.manager_id;
  if tg_op = 'UPDATE' and new.manager_id = old.manager_id then
    return null;  -- kein Besitzerwechsel, nichts zu tun
  end if;

  select season into v_season from fantasy_leagues where id = old.league_id;
  if v_season is null then return null; end if;

  -- **Nur Runden, die noch nicht angepfiffen sind.** Vorher stand hier
  -- `round >= fantasy_laufende_runde(...)` — und die laufende Runde ist genau
  -- die, deren Punkte gerade gezaehlt werden.
  update fantasy_lineups
     set player_ids = array_remove(player_ids, old.player_id),
         updated_at = now()
   where league_id = old.league_id
     and manager_id = v_mgr
     and not public.fantasy_runde_angepfiffen(season, round)
     and old.player_id = any(player_ids);

  return null;
end$$;

-- ---------------------------------------------------------------------------
-- Reparatur: die drei beschnittenen Aufstellungen
-- ---------------------------------------------------------------------------
--
-- Wiederhergestellt wird nur, was **eindeutig** ist: ein Manager, dem genau
-- ein Platz fehlt und der vor dem Stapellauf genau einen Abgang hatte. In
-- MatchUp! #1 trifft das auf beide Faelle zu (Eric verlor Nadiem Amiri,
-- Majusch Serhou Guirassy — derselbe Trade, 29.08. 07:47). Wo es mehrdeutig
-- waere, wird nichts geraten.
with beschnitten as (
  select fl.league_id, fl.manager_id, fl.season, fl.round, fl.updated_at,
         l.roster, fl.player_ids
    from fantasy_lineups fl
    join fantasy_leagues l on l.id = fl.league_id
   where cardinality(fl.player_ids) between 1 and 10
     and public.fantasy_runde_angepfiffen(fl.season, fl.round)
),
kandidaten as (
  select b.league_id, b.manager_id, b.season, b.round,
         array_agg(rm.player_id) as weg,
         public.fantasy_squad_size(b.roster) - cardinality(b.player_ids) as fehlen
    from beschnitten b
    join fantasy_roster_moves rm
      on rm.league_id = b.league_id and rm.manager_id = b.manager_id
     and rm.richtung = 'abgang' and rm.passiert_am < b.updated_at
   group by 1,2,3,4, b.roster, b.player_ids
)
update fantasy_lineups fl
   set player_ids = fl.player_ids || k.weg,
       updated_at = now()
  from kandidaten k
 where fl.league_id = k.league_id and fl.manager_id = k.manager_id
   and fl.season = k.season and fl.round = k.round
   -- Eindeutig heisst: so viele Abgaenge wie fehlende Plaetze.
   and cardinality(k.weg) = k.fehlen;
