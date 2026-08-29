-- Trades greifen erst nach dem Spieltag.
--
-- Vorfall: Ein Trade wurde **während** des Spieltags angenommen. Der
-- abgegebene Spieler verließ sofort den Kader — und damit stand die
-- Aufstellung des Betroffenen für den laufenden Spieltag nur noch mit **zehn**
-- Spielern da. Der elfte Platz war weg, die Punkte dafür auch.
--
-- Der Fehler ist nicht der Tausch, sondern sein **Zeitpunkt**: Eine
-- Kaderänderung mitten in der Wertung ändert rückwirkend die Elf, die schon
-- spielt. Deshalb wird ein angenommener Trade jetzt **vorgemerkt** und erst
-- ausgeführt, wenn der Spieltag durch ist.
--
--   Ausführung frühestens: letzter Anpfiff der laufenden Runde
--                          + 2 h (Spieldauer) + 12 h
--
-- **Läuft gerade kein Spieltag, greift der Tausch sofort** — die Verzögerung
-- soll die Wertung schützen, nicht Wartezeit erfinden. Zwischen zwei
-- Spieltagen liegt der berechnete Zeitpunkt ohnehin in der Vergangenheit.
--
-- Drei Dinge, die dabei zu beachten waren:
--
--  * **Angenommen heißt nicht mehr ausgeführt.** `status = 'accepted'` sagt
--    jetzt „beide sind sich einig"; ob die Spieler schon gewechselt sind,
--    steht in `executed_at`. Wer den Status auswertet, muss das trennen.
--  * **Zwischen Zusage und Ausführung kann sich der Kader ändern** (Free
--    Agency, ein zweiter Trade, ein Drop). Die Ausführung prüft deshalb
--    erneut, ob jeder Spieler noch beim Abgebenden liegt; sonst wird der
--    Trade abgebrochen statt halb ausgeführt. Ein halber Tausch wäre
--    schlimmer als keiner.
--  * **Der Kader-Limit-Trigger (0087) ist aufgeschoben** und prüft am Ende
--    der Transaktion — an der Ausführung ändert das nichts, sie bewegt alle
--    Spieler in einem Rutsch.

alter table fantasy_trades
  add column if not exists execute_after timestamptz,
  add column if not exists executed_at timestamptz;

comment on column fantasy_trades.execute_after is
  'Frühester Ausführungszeitpunkt eines angenommenen Trades (12 h nach dem '
  'letzten Spiel der laufenden Runde). Null bei Angeboten, die nie angenommen '
  'wurden.';
comment on column fantasy_trades.executed_at is
  'Wann die Spieler tatsächlich gewechselt sind. Null heißt: angenommen, aber '
  'noch offen.';

-- Bestehende angenommene Trades gelten als ausgeführt — sie sind es ja.
update fantasy_trades
   set executed_at = coalesce(resolved_at, created_at)
 where status = 'accepted' and executed_at is null;

-- Wann darf ein jetzt angenommener Trade greifen?
create or replace function public.fantasy_trade_frei_ab(p_league_id uuid)
returns timestamptz language plpgsql stable set search_path = public as $$
declare
  v_season int; v_letzter timestamptz;
begin
  select season into v_season from fantasy_leagues where id = p_league_id;
  if v_season is null then return now(); end if;

  -- Die Runde, die gerade läuft: erster Anpfiff vorbei, noch nicht alle
  -- Partien beendet. Gibt es keine, läuft kein Spieltag.
  select max(f.kickoff) into v_letzter
    from fixtures f
   where f.league_id = 'bundesliga'
     and f.season = v_season
     and f.round = (
       select f2.round from fixtures f2
        where f2.league_id = 'bundesliga' and f2.season = v_season
        group by f2.round
       having min(f2.kickoff) <= now()
          and bool_or(f2.status <> 'finished')
        order by min(f2.kickoff) desc
        limit 1
     );

  if v_letzter is null then return now(); end if;
  -- 2 h Spieldauer, dann die zwölf Stunden Schonfrist.
  return greatest(now(), v_letzter + interval '2 hours' + interval '12 hours');
end$$;

-- Die eigentliche Bewegung — von der sofortigen wie von der späteren
-- Ausführung benutzt, damit es nur einen Weg gibt.
create or replace function public.fantasy_trade_ausfuehren(p_trade_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
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
end$$;

create or replace function public.fantasy_respond_trade(
  p_trade_id uuid, p_accept boolean
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trade fantasy_trades;
  v_item fantasy_trade_items;
  v_frei timestamptz;
begin
  select * into v_trade from fantasy_trades where id = p_trade_id for update;
  if v_trade.id is null then raise exception 'Angebot nicht gefunden'; end if;
  if v_trade.to_manager <> v_uid then
    raise exception 'Nur der Empfänger kann auf das Angebot reagieren';
  end if;
  if v_trade.status <> 'pending' then
    raise exception 'Das Angebot ist nicht mehr offen';
  end if;

  if not p_accept then
    update fantasy_trades set status = 'rejected', resolved_at = now()
      where id = p_trade_id;
    return;
  end if;

  -- Besitz jedes Spielers prüfen, bevor überhaupt zugesagt wird.
  for v_item in select * from fantasy_trade_items where trade_id = p_trade_id loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = v_trade.league_id
                     and manager_id = v_item.giver
                     and player_id = v_item.player_id) then
      raise exception 'Spieler nicht mehr verfügbar — Angebot hinfällig';
    end if;
  end loop;

  v_frei := public.fantasy_trade_frei_ab(v_trade.league_id);
  update fantasy_trades
     set status = 'accepted', resolved_at = now(), execute_after = v_frei
   where id = p_trade_id;

  -- Kein laufender Spieltag: sofort ausführen, wie bisher.
  if v_frei <= now() then
    perform public.fantasy_trade_ausfuehren(p_trade_id);
  end if;
end$$;

-- Fällige Trades ausführen — vom Zeitplan aufgerufen.
create or replace function public.fantasy_faellige_trades_ausfuehren()
returns int language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_anzahl int := 0;
begin
  for v_id in
    select id from fantasy_trades
     where status = 'accepted'
       and executed_at is null
       and execute_after is not null
       and execute_after <= now()
     order by execute_after
  loop
    if public.fantasy_trade_ausfuehren(v_id) then
      v_anzahl := v_anzahl + 1;
    end if;
  end loop;
  return v_anzahl;
end$$;

select cron.unschedule('fantasy-trades')
  where exists (select 1 from cron.job where jobname = 'fantasy-trades');

select cron.schedule(
  'fantasy-trades',
  '*/10 * * * *',
  $$ select public.fantasy_faellige_trades_ausfuehren(); $$
);
