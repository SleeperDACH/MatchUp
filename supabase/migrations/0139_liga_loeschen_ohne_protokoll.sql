-- Eine Liga, in der gedraftet wurde, ließ sich nicht mehr löschen
-- (gemeldet 19.10.2026 an „Testtesttest").
--
-- Ursache: Das Löschen der Liga löscht per Kaskade ihre Kaderzeilen. Für jede
-- gelöschte Kaderzeile schreibt `fantasy_bewegung_protokollieren` (0096) einen
-- Abgang nach `fantasy_roster_moves` — mit der `league_id` einer Liga, die in
-- diesem Moment schon weg ist. Der Fremdschlüssel lehnt das ab (23503), und
-- das ganze Löschen rollt zurück. Betroffen war seit 0096 jede Liga mit Kader.
--
-- Abhilfe: Gibt es die Liga nicht mehr, wird nichts protokolliert. Das
-- Protokoll einer gelöschten Liga verschwindet ohnehin mit ihr (on delete
-- cascade). Die Funktion ist aus der laufenden Datenbank gezogen und nur um
-- diese eine Prüfung ergänzt.

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
    values (old.league_id, old.manager_id, old.player_id, 'abgang', null);

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
