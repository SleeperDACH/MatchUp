-- Picks für den Reset-Draft lassen sich handeln (20.10.2026, auf Ansage).
--
-- In Ligen mit Reset zur Winterpause (0143) dürfen die Manager während der
-- Hinrunde ihre Picks für den Reset-Draft tauschen — gegen Picks, gegen
-- Spieler, in jeder Mischung. Ein Pick ist **Runde + ursprüngliches Team**
-- („Runde 2 von Eric"): Die Pick-Nummer in der Runde steht erst fest, wenn
-- die Hinrunde gespielt ist (Tabellenletzter zuerst, Snake).
--
-- Drei Entscheidungen:
--
-- * **Gespeichert wird nur, was gehandelt wurde** (`fantasy_draft_rechte`).
--   Fehlt die Zeile, gehört der Pick seinem ursprünglichen Team. So braucht
--   ein neues Mitglied, eine neue Rundenzahl oder eine neue Saison keinen
--   einzigen Eintrag, und es kann keine Liste geben, die nicht vollständig ist.
-- * **Picks in Angeboten stehen in einer eigenen Tabelle**
--   (`fantasy_trade_picks`), nicht als zweite Sorte Zeile in
--   `fantasy_trade_items`. Dort ist `player_id` Teil des Primärschlüssels und
--   ältere App-Versionen lesen ihn als Pflichtfeld — eine Zeile ohne Spieler
--   ließe sie beim Öffnen der Angebote abstürzen. So sehen sie ein Angebot
--   mit Picks nur ohne die Picks.
-- * **Handelbar bis zum Reset** (`fantasy_picks_handelbar`): Liga mit Reset,
--   erster Draft fertig, Reset noch nicht erfolgt. Der Reset storniert ohnehin
--   alle offenen und vorgemerkten Trades (0143). Die Runden reichen bis zur
--   Kadergröße der Liga; wer die Rundenzahl vor dem Reset-Draft senkt, darf
--   nicht unter eine gehandelte Runde gehen (Prüfung im Start).
--
-- Im Reset-Draft zieht der **Besitzer** des Picks (`fantasy_current_manager`).
-- Ist er nicht mehr in der Liga, fällt der Pick an das ursprüngliche Team
-- zurück — sonst stünde der Draft vor einem Manager, den es nicht gibt.

create table public.fantasy_draft_rechte (
  league_id    uuid not null references public.fantasy_leagues (id) on delete cascade,
  runde        smallint not null check (runde >= 1),
  ursprung     uuid not null references public.profiles (id) on delete cascade,
  besitzer     uuid not null references public.profiles (id) on delete cascade,
  geaendert_at timestamptz not null default now(),
  primary key (league_id, runde, ursprung)
);

alter table public.fantasy_draft_rechte enable row level security;
create policy "Mitglieder sehen die Draft-Rechte" on public.fantasy_draft_rechte
  for select using (public.is_fantasy_member(league_id));

create table public.fantasy_trade_picks (
  trade_id uuid not null references public.fantasy_trades (id) on delete cascade,
  giver    uuid not null references public.profiles (id) on delete cascade,
  runde    smallint not null check (runde >= 1),
  ursprung uuid not null references public.profiles (id) on delete cascade,
  primary key (trade_id, runde, ursprung)
);

alter table public.fantasy_trade_picks enable row level security;
create policy "Beteiligte sehen die Trade-Picks" on public.fantasy_trade_picks
  for select using (exists (
    select 1 from public.fantasy_trades t
     where t.id = fantasy_trade_picks.trade_id
       and (t.from_manager = auth.uid() or t.to_manager = auth.uid())));

alter publication supabase_realtime add table public.fantasy_draft_rechte;
alter publication supabase_realtime add table public.fantasy_trade_picks;

-- Wem gehört der Pick?
create or replace function public.fantasy_pick_besitzer(
  p_league_id uuid, p_runde int, p_ursprung uuid)
returns uuid language sql stable security definer set search_path to 'public' as $$
  select coalesce(
    (select besitzer from fantasy_draft_rechte
      where league_id = p_league_id and runde = p_runde and ursprung = p_ursprung),
    p_ursprung);
$$;

-- Dürfen in dieser Liga gerade Picks gehandelt werden?
create or replace function public.fantasy_picks_handelbar(p_league_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((select reset_aktiv and reset_erfolgt_at is null
                          and draft_status = 'done'
                     from fantasy_leagues where id = p_league_id), false);
$$;

create or replace function public.fantasy_runden(p_league_id uuid)
returns int language sql stable security definer set search_path to 'public' as $$
  select coalesce((roster->>'gk')::int, 1) + coalesce((roster->>'def')::int, 4)
       + coalesce((roster->>'mid')::int, 4) + coalesce((roster->>'fwd')::int, 2)
       + coalesce((roster->>'bench')::int, 5)
    from fantasy_leagues where id = p_league_id;
$$;

-- Prüft einen Pick in einem Angebot; wirft mit verständlicher Meldung.
create or replace function public._fantasy_pick_pruefen(
  p_league_id uuid, p_runde int, p_ursprung uuid, p_giver uuid)
returns void language plpgsql stable security definer set search_path to 'public' as $$
begin
  if p_runde < 1 or p_runde > public.fantasy_runden(p_league_id) then
    raise exception 'Diese Runde gibt es im Reset-Draft nicht';
  end if;
  if not exists (select 1 from fantasy_league_members
                  where league_id = p_league_id and user_id = p_ursprung) then
    raise exception 'Der Pick gehört zu keinem Team dieser Liga';
  end if;
  if public.fantasy_pick_besitzer(p_league_id, p_runde, p_ursprung) <> p_giver then
    raise exception 'Der Pick liegt nicht beim Abgebenden — Angebot hinfällig';
  end if;
end $$;

-- Angebot mit Spielern und Picks. Die alte Signatur fällt weg; PostgREST ruft
-- mit Namen auf, ältere Apps schicken die beiden neuen Felder einfach nicht.
drop function if exists public.fantasy_propose_trade(uuid, uuid, text[], text[], text, uuid);

create or replace function public.fantasy_propose_trade(
  p_league_id uuid, p_to_manager uuid, p_offer_players text[],
  p_request_players text[], p_message text, p_counter_of uuid default null,
  p_offer_picks jsonb default '[]'::jsonb, p_request_picks jsonb default '[]'::jsonb)
returns uuid
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_uid uuid := auth.uid();
  v_trade_id uuid;
  v_pid text;
  v_pick jsonb;
  v_offer_picks jsonb := coalesce(p_offer_picks, '[]'::jsonb);
  v_request_picks jsonb := coalesce(p_request_picks, '[]'::jsonb);
begin
  if v_uid is null then raise exception 'Nicht angemeldet'; end if;
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  if v_uid = p_to_manager then raise exception 'Kein Trade mit dir selbst'; end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = p_to_manager
                   and not vacant) then
    raise exception 'Der Empfänger ist kein Mitglied dieser Liga';
  end if;
  if coalesce(array_length(p_offer_players, 1), 0) = 0
     and coalesce(array_length(p_request_players, 1), 0) = 0
     and jsonb_array_length(v_offer_picks) = 0
     and jsonb_array_length(v_request_picks) = 0 then
    raise exception 'Ein Angebot braucht mindestens einen Spieler oder Pick';
  end if;
  if (jsonb_array_length(v_offer_picks) > 0 or jsonb_array_length(v_request_picks) > 0)
     and not public.fantasy_picks_handelbar(p_league_id) then
    raise exception 'Picks lassen sich nur während der Hinrunde handeln';
  end if;

  foreach v_pid in array coalesce(p_offer_players, '{}') loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and manager_id = v_uid
                     and player_id = v_pid) then
      raise exception 'Angebotener Spieler nicht in deinem Kader';
    end if;
  end loop;
  foreach v_pid in array coalesce(p_request_players, '{}') loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = p_league_id and manager_id = p_to_manager
                     and player_id = v_pid) then
      raise exception 'Geforderter Spieler nicht im Kader des Empfängers';
    end if;
  end loop;
  for v_pick in select * from jsonb_array_elements(v_offer_picks) loop
    perform public._fantasy_pick_pruefen(p_league_id, (v_pick->>'runde')::int,
      (v_pick->>'ursprung')::uuid, v_uid);
  end loop;
  for v_pick in select * from jsonb_array_elements(v_request_picks) loop
    perform public._fantasy_pick_pruefen(p_league_id, (v_pick->>'runde')::int,
      (v_pick->>'ursprung')::uuid, p_to_manager);
  end loop;

  insert into fantasy_trades (league_id, from_manager, to_manager, message)
    values (p_league_id, v_uid, p_to_manager,
            nullif(btrim(coalesce(p_message, '')), ''))
    returning id into v_trade_id;

  foreach v_pid in array coalesce(p_offer_players, '{}') loop
    insert into fantasy_trade_items (trade_id, giver, player_id)
      values (v_trade_id, v_uid, v_pid);
  end loop;
  foreach v_pid in array coalesce(p_request_players, '{}') loop
    insert into fantasy_trade_items (trade_id, giver, player_id)
      values (v_trade_id, p_to_manager, v_pid);
  end loop;
  insert into fantasy_trade_picks (trade_id, giver, runde, ursprung)
    select v_trade_id, v_uid, (e->>'runde')::int, (e->>'ursprung')::uuid
      from jsonb_array_elements(v_offer_picks) e
    union
    select v_trade_id, p_to_manager, (e->>'runde')::int, (e->>'ursprung')::uuid
      from jsonb_array_elements(v_request_picks) e;

  -- Gegenangebot: das ursprüngliche (offene) Angebot schließen. Nur der
  -- Empfänger des Originals (= jetziger Absender) darf es kontern.
  if p_counter_of is not null then
    update fantasy_trades set status = 'countered', resolved_at = now()
      where id = p_counter_of and to_manager = v_uid and status = 'pending';
  end if;

  return v_trade_id;
end$function$;

grant execute on function public.fantasy_propose_trade(
  uuid, uuid, text[], text[], text, uuid, jsonb, jsonb) to authenticated;

create or replace function public.fantasy_respond_trade(p_trade_id uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_uid uuid := auth.uid();
  v_trade fantasy_trades;
  v_item fantasy_trade_items;
  v_pick fantasy_trade_picks;
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

  -- Besitz jedes Spielers und Picks prüfen, bevor überhaupt zugesagt wird.
  for v_item in select * from fantasy_trade_items where trade_id = p_trade_id loop
    if not exists (select 1 from fantasy_rosters
                   where league_id = v_trade.league_id
                     and manager_id = v_item.giver
                     and player_id = v_item.player_id) then
      raise exception 'Spieler nicht mehr verfügbar — Angebot hinfällig';
    end if;
  end loop;
  if exists (select 1 from fantasy_trade_picks where trade_id = p_trade_id)
     and not public.fantasy_picks_handelbar(v_trade.league_id) then
    raise exception 'Picks lassen sich nur während der Hinrunde handeln';
  end if;
  for v_pick in select * from fantasy_trade_picks where trade_id = p_trade_id loop
    perform public._fantasy_pick_pruefen(v_trade.league_id, v_pick.runde,
      v_pick.ursprung, v_pick.giver);
  end loop;

  v_frei := public.fantasy_trade_frei_ab(v_trade.league_id);
  update fantasy_trades
     set status = 'accepted', resolved_at = now(), execute_after = v_frei
   where id = p_trade_id;

  -- Kein laufender Spieltag: sofort ausführen, wie bisher.
  if v_frei <= now() then
    perform public.fantasy_trade_ausfuehren(p_trade_id);
  end if;
end$function$;

create or replace function public.fantasy_trade_ausfuehren(p_trade_id uuid)
returns boolean
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_trade fantasy_trades; v_item fantasy_trade_items; v_pick fantasy_trade_picks;
  v_other uuid;
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
  for v_pick in select * from fantasy_trade_picks where trade_id = p_trade_id loop
    if public.fantasy_pick_besitzer(v_trade.league_id, v_pick.runde, v_pick.ursprung)
         <> v_pick.giver
       or not public.fantasy_picks_handelbar(v_trade.league_id) then
      update fantasy_trades
         set status = 'cancelled', resolved_at = now()
       where id = p_trade_id;
      perform public.fantasy_post_system_message(
        v_trade.league_id,
        '⚠️ Ein vorgemerkter Trade ist hinfällig: Ein Pick für den Reset-Draft '
          || 'ist nicht mehr beim Abgebenden.');
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
  for v_pick in select * from fantasy_trade_picks where trade_id = p_trade_id loop
    v_other := case when v_pick.giver = v_trade.from_manager
                    then v_trade.to_manager else v_trade.from_manager end;
    insert into fantasy_draft_rechte (league_id, runde, ursprung, besitzer)
      values (v_trade.league_id, v_pick.runde, v_pick.ursprung, v_other)
      on conflict (league_id, runde, ursprung)
      do update set besitzer = excluded.besitzer, geaendert_at = now();
  end loop;

  update fantasy_trades set executed_at = now() where id = p_trade_id;
  return true;
end$function$;

-- Wer am Zug ist: in der Reset-Phase der **Besitzer** des Picks.
create or replace function public.fantasy_current_manager(p_league_id uuid)
 returns uuid
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_p int; v_n int; v_round0 int; v_pos int; v_slot int; v_manager uuid;
  v_phase text; v_besitzer uuid;
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
  if v_phase = 'reset' and v_manager is not null then
    v_besitzer := public.fantasy_pick_besitzer(p_league_id, v_round0 + 1, v_manager);
    if exists (select 1 from fantasy_league_members
                where league_id = p_league_id and user_id = v_besitzer) then
      return v_besitzer;
    end if;
  end if;
  return v_manager;
end$function$;

-- Der Reset-Draft startet nicht mit weniger Runden, als gehandelt wurden.
create or replace function public.fantasy_reset_draft_starten(
  p_league_id uuid, p_reihenfolge uuid[])
returns void
language plpgsql security definer set search_path to 'public' as $$
declare v_created_by uuid; v_status text; v_secs int; v_n int; v_max int;
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

  select max(runde) into v_max from fantasy_draft_rechte
   where league_id = p_league_id and besitzer <> ursprung;
  if v_max is not null and v_max > public.fantasy_runden(p_league_id) then
    raise exception 'Runde % wurde gehandelt — der Draft braucht mindestens % Runden',
      v_max, v_max;
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

revoke all on function public._fantasy_pick_pruefen(uuid, int, uuid, uuid) from public, anon, authenticated;
grant execute on function public.fantasy_pick_besitzer(uuid, int, uuid) to authenticated;
grant execute on function public.fantasy_picks_handelbar(uuid) to authenticated;
