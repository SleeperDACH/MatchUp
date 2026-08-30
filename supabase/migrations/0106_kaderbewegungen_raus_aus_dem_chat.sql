-- Kaderbewegungen und Trades verschwinden aus dem Liga-Chat.
--
-- Seit dem Transfers-Bereich (0096/0097) hat die Liga eine eigene Seite fuer
-- genau diese Auskunft: eigene Vorgaenge auf der einen Seite, die Bewegungen
-- der ganzen Liga auf der anderen, mit Zu- und Abgang nebeneinander. Der Chat
-- meldete dasselbe ein zweites Mal — 99 automatische Zeilen in acht Wochen,
-- zwischen denen die Gespraeche der Mitglieder untergingen. Ein Chat ist fuer
-- das da, was Menschen einander schreiben.
--
-- **Es geht dabei nichts verloren.** Das Protokoll haengt an einem Trigger auf
-- `fantasy_rosters` (0096) und erfasst deshalb jeden Weg, ueber den ein
-- Spieler kommt oder geht — auch die Admin-Korrektur und den Waiver-Zuschlag.
-- Die Chat-Zeilen waren die zweite, schlechtere Kopie.
--
-- **Eine Meldung bleibt:** die Warnung, dass ein vorgemerkter Trade hinfaellig
-- geworden ist (`fantasy_trade_ausfuehren`). Sie meldet nicht, was geschehen
-- ist, sondern dass etwas Erwartetes **nicht** geschehen ist — dafuer gibt es
-- im Transfers-Bereich keinen Platz, und wer auf den Spieler wartet, muss es
-- erfahren. `fantasy_post_system_message` bleibt dafuer bestehen.
--
-- Die Funktionen stehen hier vollstaendig, so wie sie in der Datenbank
-- stehen; entfernt sind nur die `perform`-Zeilen. Sie aus den alten
-- Migrationen zusammenzusuchen waere ein Rueckschritt gewesen: 0029, 0032,
-- 0044, 0088, 0094 und 0095 haben jede von ihnen seither angefasst.

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

end$function$
;

CREATE OR REPLACE FUNCTION public.fantasy_admin_add(p_league_id uuid, p_target uuid, p_player_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.fantasy_is_admin(p_league_id) then
    raise exception 'Nur der Admin darf Kader bearbeiten';
  end if;
  if not exists (select 1 from players where id = p_player_id) then
    raise exception 'Spieler unbekannt';
  end if;
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = p_target and not vacant) then
    raise exception 'Zielteam ist kein aktives Mitglied';
  end if;
  delete from fantasy_waiver_players
    where league_id = p_league_id and player_id = p_player_id;
  insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
    values (p_league_id, p_target, p_player_id, 'fa');
end$function$
;

CREATE OR REPLACE FUNCTION public.fantasy_admin_drop(p_league_id uuid, p_target uuid, p_player_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.fantasy_is_admin(p_league_id) then
    raise exception 'Nur der Admin darf Kader bearbeiten';
  end if;
  if not exists (select 1 from fantasy_rosters
                 where league_id = p_league_id and player_id = p_player_id
                   and manager_id = p_target) then
    raise exception 'Spieler nicht im Kader dieses Teams';
  end if;
  delete from fantasy_rosters
    where league_id = p_league_id and player_id = p_player_id and manager_id = p_target;
  perform public.fantasy_put_on_wire(p_league_id, p_player_id);
end$function$
;

CREATE OR REPLACE FUNCTION public.fantasy_drop_player(p_league_id uuid, p_player_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end$function$
;

CREATE OR REPLACE FUNCTION public.fantasy_process_due_waivers()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  w record; v_claim record; v_squad int; v_have int; v_frees int; v_awarded boolean;
begin
  for w in
    select league_id, player_id from fantasy_waiver_players
    where clears_at <= now() order by clears_at
  loop
    if exists (select 1 from fantasy_rosters
               where league_id = w.league_id and player_id = w.player_id) then
      delete from fantasy_waiver_players
        where league_id = w.league_id and player_id = w.player_id;
      continue;
    end if;

    select public.fantasy_squad_size(roster) into v_squad
      from fantasy_leagues where id = w.league_id;
    v_awarded := false;

    for v_claim in
      select c.*
      from fantasy_waiver_claims c
      join fantasy_league_members m
        on m.league_id = c.league_id and m.user_id = c.manager_id and not m.vacant
      where c.league_id = w.league_id and c.add_player_id = w.player_id
        and c.status = 'pending'
      order by m.waiver_priority asc nulls last, c.rank asc, c.created_at asc
    loop
      v_frees := 0;
      if v_claim.drop_player_id is not null and exists (
           select 1 from fantasy_rosters
           where league_id = w.league_id and player_id = v_claim.drop_player_id
             and manager_id = v_claim.manager_id) then
        v_frees := 1;
      end if;
      select count(*) into v_have from fantasy_rosters
        where league_id = w.league_id and manager_id = v_claim.manager_id;
      if v_have - v_frees >= v_squad then
        update fantasy_waiver_claims set status = 'invalid',
               reason = 'Kader voll – Drop nötig', processed_at = now()
          where id = v_claim.id;
        continue;
      end if;

      if v_frees = 1 then
        delete from fantasy_rosters
          where league_id = w.league_id and player_id = v_claim.drop_player_id
            and manager_id = v_claim.manager_id;
        perform public.fantasy_put_on_wire(w.league_id, v_claim.drop_player_id);
      end if;
      insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
        values (w.league_id, v_claim.manager_id, w.player_id, 'waiver');
      update fantasy_waiver_claims set status = 'won', processed_at = now()
        where id = v_claim.id;
      update fantasy_league_members
        set waiver_priority = (select coalesce(max(waiver_priority), 0) + 1
                               from fantasy_league_members
                               where league_id = w.league_id and not vacant)
        where league_id = w.league_id and user_id = v_claim.manager_id;
      v_awarded := true;
      exit;
    end loop;

    delete from fantasy_waiver_players
      where league_id = w.league_id and player_id = w.player_id;
    update fantasy_waiver_claims
      set status = 'lost',
          reason = case when v_awarded then 'Spieler anderweitig vergeben'
                        else 'Frist abgelaufen – Spieler frei' end,
          processed_at = now()
      where league_id = w.league_id and add_player_id = w.player_id
        and status = 'pending';
  end loop;
end$function$
;

CREATE OR REPLACE FUNCTION public.fantasy_trade_ausfuehren(p_trade_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_trade fantasy_trades; v_item fantasy_trade_items; v_other uuid;
begin
  select * into v_trade from fantasy_trades where id = p_trade_id for update;
  if v_trade.id is null or v_trade.executed_at is not null then
    return false;
  end if;

  -- Besitz erneut prüfen: Zwischen Zusage und Ausführung kann sich der Kader
  -- geändert haben. Lieber abbrechen als halb ausführen.
  for v_item in select * from fantasy_trade_items where trade_id = p_trade_id loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = v_trade.league_id
                     and manager_id = v_item.giver
                     and player_id = v_item.player_id) then
      update fantasy_trades
         set status = 'cancelled', resolved_at = now()
       where id = p_trade_id;
      perform public.fantasy_post_system_message(
        v_trade.league_id,
        '⚠️ Ein vorgemerkter Trade ist hinfällig: '
          || public._fantasy_playername(v_item.player_id)
          || ' ist nicht mehr im Kader des Abgebenden.');
      return false;
    end if;
  end loop;

  for v_item in select * from fantasy_trade_items where trade_id = p_trade_id loop
    v_other := case when v_item.giver = v_trade.from_manager
                    then v_trade.to_manager else v_trade.from_manager end;
    update fantasy_rosters
       set manager_id = v_other, acquired_via = 'trade', acquired_at = now()
     where league_id = v_trade.league_id and player_id = v_item.player_id;
  end loop;

  update fantasy_trades set executed_at = now() where id = p_trade_id;
  return true;
end$function$;


-- ---------------------------------------------------------------------------
-- Die bereits geschriebenen Meldungen aus dem Verlauf nehmen
-- ---------------------------------------------------------------------------
-- Alle vier Sorten (✅ Verpflichtung, 🔻 Abgabe, 📥 Waiver, 🛠️ Admin) sind
-- Kaderbewegungen und stehen im Protokoll. Die ⚠️-Warnung bleibt.
delete from public.fantasy_league_messages
 where is_system
   and body not like '⚠️%';

-- Die Trade-Meldungen kamen nicht vom Server, sondern von der App: Wer ein
-- Angebot annahm, schrieb den Text als **normale Nachricht** in den Chat
-- (`_postTradeToChat`). Deshalb tragen sie einen Absender und sind an ihrem
-- Anfang zu erkennen. Der Praefix ist streng gewaehlt — im Verlauf steht auch
-- eine echte Nachricht, die nur aus einem Emoji besteht.
delete from public.fantasy_league_messages
 where not is_system
   and body like '🔄 Trade angenommen: %';
