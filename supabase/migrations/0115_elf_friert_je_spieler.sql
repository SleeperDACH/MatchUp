-- Praeziser als 0113: Ein Spieler friert in der Elf **ab seinem eigenen
-- Anpfiff** ein, nicht ab dem ersten Anpfiff der Runde.
--
-- 0113 hat die ganze Runde gesperrt, sobald ihr erstes Spiel lief. Das
-- verhindert den gemeldeten Fehler, geht aber zu weit: Wer freitags einen
-- Sonntagsspieler abgibt, muss ihn auch aus der Elf verlieren — sonst
-- punktete am Sonntag ein Spieler fuer ein Team, das ihn seit Freitag nicht
-- mehr hat.
--
-- Die richtige Grenze ist dieselbe wie bei der Aufstellungssperre (0084):
-- **der Anpfiff seines Vereins.** Davor darf er aus der Elf fallen, danach
-- nie mehr.
--
-- Vergangene Spieltage sind damit automatisch geschuetzt — dort liegt sein
-- Anpfiff in der Vergangenheit. Es braucht keine zweite Regel dafuer, und
-- genau die zweite Regel („round >= laufende Runde") war der Fehler: Sie
-- hielt die laufende Runde faelschlich fuer Zukunft.

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

  update fantasy_lineups fl
     set player_ids = array_remove(fl.player_ids, old.player_id),
         updated_at = now()
   where fl.league_id = old.league_id
     and fl.manager_id = v_mgr
     and old.player_id = any(fl.player_ids)
     -- **Nur solange sein Spiel dieser Runde noch nicht angepfiffen ist.**
     -- Kein Spiel in der Runde (`null`) heisst: raus damit — punkten kann er
     -- dort ohnehin nicht, und eine Elf mit einem Spieler ohne Ansetzung
     -- waere eine Luecke, die niemand sieht.
     and coalesce(
           public.fantasy_spieler_anpfiff(v_season, fl.round, old.player_id),
           'infinity'::timestamptz) > now();

  return null;
end$$;
