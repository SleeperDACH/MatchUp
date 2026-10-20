-- **Der Wochenrückblick erscheint mit dem Wechsel auf den nächsten Spieltag,
-- und alle bekommen eine Push-Benachrichtigung** (19.10.2026, auf Ansage).
--
-- Der Wechsel ist die Waiver-Frist der Runde (Montag 15:00, in englischen
-- Wochen Donnerstag 15:00): Dann springt `currentFantasyRound` in der App
-- weiter, und genau dann vermerkt `fantasy_waivers_faellig` (alle 5 Minuten)
-- einmal je Liga und Runde einen Eintrag in `fantasy_waiver_laeufe`. An diese
-- Stelle hängt der Push — derselbe Zeitpunkt, an dem die App den Rückblick
-- freigibt (`rueckblickVeroeffentlicht`), ohne zweite Uhr.
--
-- Neue Push-Sorte `wochenrueckblick` (Bereich Fantasy): Spalte in
-- `push_einstellungen` (fehlende Zeile = an, wie alle) und Eintrag im Check.
-- Gemeldet wird nur in Ligen, deren Draft durch ist, und nur an aktive
-- Mitglieder (nicht verwaist, nicht wartend). Der Schlüssel
-- `rueckblick:<liga>:<runde>:<nutzer>` verhindert eine Doppelmeldung.

alter table public.push_einstellungen
  add column if not exists wochenrueckblick boolean not null default true;

alter table public.push_auftraege
  drop constraint if exists push_auftraege_kategorie_check;
alter table public.push_auftraege
  add constraint push_auftraege_kategorie_check check (kategorie in (
    -- Fantasy
    'draft', 'trades', 'waiver', 'ausfaelle', 'liga_chat', 'liga_anfragen',
    'wochenrueckblick',
    -- Tippspiel
    'tipps', 'runden_chat', 'runden_anfragen',
    -- Live
    'live_anpfiff', 'live_tore', 'live_rote_karten', 'live_halbzeit',
    'live_endstand',
    -- Allgemein
    'direktnachrichten', 'freunde',
    -- Alt (0129), nur damit vorhandene Zeilen gültig bleiben
    'nachrichten', 'anfragen'));

-- Meldet allen aktiven Mitgliedern einer Liga den Rückblick auf [p_runde].
create or replace function public.fantasy_rueckblick_melden(
  p_league_id uuid,
  p_runde int
) returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name text; v_status text; m record; n int := 0;
begin
  select name, draft_status into v_name, v_status
    from fantasy_leagues where id = p_league_id;
  if v_name is null or v_status <> 'done' then return 0; end if;

  for m in
    select user_id from fantasy_league_members
     where league_id = p_league_id
       and not coalesce(vacant, false)
       and not coalesce(pending, false)
  loop
    if public.push_anlegen(
         m.user_id,
         'wochenrueckblick',
         'Wochenrückblick · Spieltag ' || p_runde,
         'In „' || v_name || '" steht der Rückblick: Team der Woche, MVP '
           || 'und die knappsten Duelle.',
         jsonb_build_object('art', 'fantasy', 'id', p_league_id::text,
                            'kategorie', 'wochenrueckblick',
                            'runde', p_runde),
         -- Mit Nutzer: Der Index auf `schluessel` gilt über alle Aufträge,
         -- ohne Nutzer bekäme nur der erste Manager seine Meldung.
         'rueckblick:' || p_league_id || ':' || p_runde || ':' || m.user_id)
    then
      n := n + 1;
    end if;
  end loop;
  return n;
end
$$;

revoke all on function public.fantasy_rueckblick_melden(uuid, int)
  from public, anon, authenticated;

-- Aus der laufenden Datenbank (0107), ergänzt um den Push nach dem Vermerk.
create or replace function public.fantasy_waivers_faellig()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
    -- Der Rückblick auf diese Runde ist ab jetzt sichtbar (0141).
    perform public.fantasy_rueckblick_melden(l.id, v_runde);
    n := n + 1;
  end loop;
  return n;
end$function$;
