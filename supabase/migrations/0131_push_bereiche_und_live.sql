-- Push: vier Bereiche, Live-Meldungen, Trades an die ganze Liga, Tipps drei
-- Stunden vorher. Auf Ansage (06.10.2026).
--
-- **Die Einstellungen sind jetzt nach Bereichen geschnitten** — Fantasy,
-- Tippspiel, Live, Allgemein — und nicht mehr nach Art des Ereignisses. Die
-- beiden Sammelsorten aus 0129 passten in keinen Bereich: „Nachrichten" war
-- Liga-Chat (Fantasy), Tipprunden-Chat (Tippspiel) und Direktnachricht
-- (Allgemein) zugleich, „Anfragen" ebenso. Beide sind in ihre Teile zerlegt;
-- wer eine davon abgeschaltet hatte, findet alle Teile abgeschaltet vor.
--
-- **Live meldet nur an Fans.** Empfänger sind alle, die einen der beiden
-- Vereine unter ihren Favoriten haben (`user_favorites`, `fav_type = 'team'`).
-- Ein Liga-Favorit zählt nicht — ein Tor in jedem Bundesligaspiel wäre
-- Lärm, kein Hinweis.
--
-- **Live braucht einen eigenen Abgleich.** `fixtures` kennt nur Spielstand
-- und drei Zustände und wird alle zehn Minuten gespiegelt; Halbzeit und Rote
-- Karten stehen dort gar nicht. Die Edge Function `sync-live` holt deshalb
-- jede Minute die laufenden Spiele samt Ereignissen bei Sportmonks und reicht
-- je Spiel einen Schnappschuss an `push_live_abgleich`. Was neu ist, stellt
-- die Datenbank fest, nicht die Function: Vergleich, Aufträge und neuer Stand
-- liegen damit in **einer** Transaktion, und ein abgebrochener Lauf meldet
-- nichts doppelt.
--
-- **Nebenbei geschlossen:** `push_anlegen` war für `anon` und `authenticated`
-- ausführbar — jeder hätte über `/rpc/push_anlegen` jedem Nutzer einen
-- beliebigen Text aufs Handy schicken können. Siehe Abschnitt 8.

-- ---------------------------------------------------------------------
-- 1) Einstellungen: neue Spalten, alte Werte übernommen
-- ---------------------------------------------------------------------
alter table public.push_einstellungen
  add column if not exists liga_chat         boolean not null default true,
  add column if not exists liga_anfragen     boolean not null default true,
  add column if not exists runden_chat       boolean not null default true,
  add column if not exists runden_anfragen   boolean not null default true,
  add column if not exists live_anpfiff      boolean not null default true,
  add column if not exists live_tore         boolean not null default true,
  add column if not exists live_rote_karten  boolean not null default true,
  add column if not exists live_halbzeit     boolean not null default true,
  add column if not exists live_endstand     boolean not null default true,
  add column if not exists direktnachrichten boolean not null default true,
  add column if not exists freunde           boolean not null default true;

update public.push_einstellungen
   set liga_chat         = nachrichten,
       runden_chat       = nachrichten,
       direktnachrichten = nachrichten,
       liga_anfragen     = anfragen,
       runden_anfragen   = anfragen,
       freunde           = anfragen;

-- `nachrichten` und `anfragen` bleiben stehen, werden aber nicht mehr
-- gelesen: Ältere App-Versionen schreiben beim Umschalten den ganzen Satz
-- samt dieser beiden Spalten — fehlten sie, schlüge dort jedes Speichern fehl.
-- Wegräumen, sobald keine Version vor dieser Migration mehr im Umlauf ist.
comment on column public.push_einstellungen.nachrichten is
  'Veraltet seit 0131 (zerlegt in liga_chat, runden_chat, direktnachrichten).';
comment on column public.push_einstellungen.anfragen is
  'Veraltet seit 0131 (zerlegt in liga_anfragen, runden_anfragen, freunde).';

-- ---------------------------------------------------------------------
-- 2) Ausgangskorb: die neuen Sorten
-- ---------------------------------------------------------------------
alter table public.push_auftraege
  drop constraint if exists push_auftraege_kategorie_check;
alter table public.push_auftraege
  add constraint push_auftraege_kategorie_check check (kategorie in (
    -- Fantasy
    'draft', 'trades', 'waiver', 'ausfaelle', 'liga_chat', 'liga_anfragen',
    -- Tippspiel
    'tipps', 'runden_chat', 'runden_anfragen',
    -- Live
    'live_anpfiff', 'live_tore', 'live_rote_karten', 'live_halbzeit',
    'live_endstand',
    -- Allgemein
    'direktnachrichten', 'freunde',
    -- Alt (0129), nur damit vorhandene Zeilen gültig bleiben
    'nachrichten', 'anfragen'));

-- ---------------------------------------------------------------------
-- 3) push_anlegen: Schalter per Spaltenname
-- ---------------------------------------------------------------------
-- Statt eines `case` mit einem Zweig je Sorte liest die Funktion die Spalte,
-- die so heißt wie die Kategorie. Eine neue Sorte braucht damit nur noch ihre
-- Spalte und den Eintrag im Check oben — der `case` aus 0129 wäre die dritte
-- Stelle gewesen, und die vergessene liefe still auf „an".
create or replace function public.push_anlegen(
  p_user       uuid,
  p_kategorie  text,
  p_titel      text,
  p_text       text,
  p_ziel       jsonb default '{}'::jsonb,
  p_schluessel text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_an boolean;
  v_id bigint;
begin
  if p_user is null then return false; end if;

  if not exists (select 1 from push_geraete where user_id = p_user) then
    return false;
  end if;

  select (to_jsonb(e) -> p_kategorie)::boolean
    into v_an
    from push_einstellungen e
   where e.user_id = p_user;

  -- Keine Zeile = alles an (siehe 0129).
  if v_an is not null and v_an = false then return false; end if;

  insert into push_auftraege (user_id, kategorie, titel, text, ziel, schluessel)
  values (p_user, p_kategorie, p_titel, p_text, coalesce(p_ziel, '{}'::jsonb),
          p_schluessel)
  on conflict do nothing
  returning id into v_id;

  return v_id is not null;
end$$;

-- ---------------------------------------------------------------------
-- 4) Auslöser auf die neuen Sorten
-- ---------------------------------------------------------------------

-- 4.1 Trades. Neu: Ein angenommener Trade geht an **alle** in der Liga. Der
-- Anbieter bekommt wie bisher „Trade angenommen", der Annehmende nichts (er
-- hat eben selbst getippt), alle übrigen erfahren, wer wen tauscht.
--
-- Angenommen heißt seit 0088 nicht ausgeführt — vollzogen wird nach dem
-- Spieltag. Gemeldet wird trotzdem beim Annehmen: Das ist der Moment, über
-- den in der Liga geredet wird.
create or replace function public.push_trade()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_liga text; v_von text; v_an text; v_gibt text; v_bekommt text; r record;
begin
  select name into v_liga from fantasy_leagues where id = new.league_id;
  select username into v_von from profiles where id = new.from_manager;
  select username into v_an from profiles where id = new.to_manager;

  if tg_op = 'INSERT' and new.status = 'pending' then
    perform public.push_anlegen(
      new.to_manager, 'trades',
      'Neues Trade-Angebot',
      format('%s bietet dir einen Trade an · %s', coalesce(v_von, 'Ein Manager'), v_liga),
      jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
      format('trade-neu:%s', new.id));
    return null;
  end if;

  if tg_op <> 'UPDATE' or new.status is not distinct from old.status
     or new.status not in ('accepted', 'rejected') then
    return null;
  end if;

  perform public.push_anlegen(
    new.from_manager, 'trades',
    case new.status when 'accepted' then 'Trade angenommen'
                    else 'Trade abgelehnt' end,
    format('%s · %s', coalesce(v_an, 'Der Manager'), v_liga),
    jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
    format('trade-%s:%s', new.status, new.id));

  if new.status <> 'accepted' then return null; end if;

  -- Wer was abgibt, aus den Positionen des Trades.
  select string_agg(p.name, ', ' order by p.name) filter (where it.giver = new.from_manager),
         string_agg(p.name, ', ' order by p.name) filter (where it.giver = new.to_manager)
    into v_gibt, v_bekommt
    from fantasy_trade_items it
    join players p on p.id = it.player_id
   where it.trade_id = new.id;

  for r in select user_id from fantasy_league_members
            where league_id = new.league_id
              and user_id not in (new.from_manager, new.to_manager) loop
    perform public.push_anlegen(
      r.user_id, 'trades',
      format('Trade in %s', v_liga),
      format('%s ⇄ %s: %s gegen %s',
             coalesce(v_von, 'Ein Manager'), coalesce(v_an, 'ein Manager'),
             coalesce(v_gibt, '–'), coalesce(v_bekommt, '–')),
      jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
      format('trade-liga:%s:%s', new.id, r.user_id));
  end loop;
  return null;
end$$;

-- 4.2 Direktnachricht → Allgemein.
create or replace function public.push_direktnachricht()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_von text;
begin
  select username into v_von from profiles where id = new.sender_id;
  perform public.push_anlegen(
    new.recipient_id, 'direktnachrichten',
    coalesce(v_von, 'Neue Nachricht'),
    left(new.body, 140),
    jsonb_build_object('art', 'nachrichten', 'id', new.sender_id::text),
    format('dm:%s:%s', new.recipient_id, new.sender_id));
  return null;
end$$;

-- 4.3 Liga-Chat → Fantasy, Tipprunden-Chat → Tippspiel.
create or replace function public.push_liga_chat()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_von text; v_liga text; r record;
begin
  select username into v_von from profiles where id = new.user_id;
  select name into v_liga from fantasy_leagues where id = new.league_id;
  for r in select user_id from fantasy_league_members
            where league_id = new.league_id and user_id <> new.user_id loop
    perform public.push_anlegen(
      r.user_id, 'liga_chat',
      format('%s · %s', coalesce(v_von, 'Neue Nachricht'), v_liga),
      left(new.body, 140),
      jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
      format('ligachat:%s:%s', new.league_id, r.user_id));
  end loop;
  return null;
end$$;

create or replace function public.push_runden_chat()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_von text; v_runde text; r record;
begin
  select username into v_von from profiles where id = new.user_id;
  select name into v_runde from tip_rounds where id = new.round_id;
  for r in select user_id from tip_round_members
            where round_id = new.round_id and user_id <> new.user_id loop
    perform public.push_anlegen(
      r.user_id, 'runden_chat',
      format('%s · %s', coalesce(v_von, 'Neue Nachricht'), v_runde),
      left(new.body, 140),
      jsonb_build_object('art', 'tipprunde', 'id', new.round_id::text),
      format('rundenchat:%s:%s', new.round_id, r.user_id));
  end loop;
  return null;
end$$;

-- 4.4 Beitrittsanfragen in ihren Bereich, Freundschaften → Allgemein.
create or replace function public.push_beitritt_fantasy()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_liga text; v_admin uuid; v_wer text;
begin
  select name, created_by into v_liga, v_admin
    from fantasy_leagues where id = new.league_id;
  select username into v_wer from profiles where id = new.user_id;
  perform public.push_anlegen(
    v_admin, 'liga_anfragen',
    'Beitrittsanfrage',
    format('%s möchte in %s', coalesce(v_wer, 'Jemand'), v_liga),
    jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
    format('beitritt-f:%s:%s', new.league_id, new.user_id));
  return null;
end$$;

create or replace function public.push_beitritt_tipp()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_runde text; v_admin uuid; v_wer text;
begin
  select name, created_by into v_runde, v_admin
    from tip_rounds where id = new.round_id;
  select username into v_wer from profiles where id = new.user_id;
  perform public.push_anlegen(
    v_admin, 'runden_anfragen',
    'Beitrittsanfrage',
    format('%s möchte in %s', coalesce(v_wer, 'Jemand'), v_runde),
    jsonb_build_object('art', 'tipprunde', 'id', new.round_id::text),
    format('beitritt-t:%s:%s', new.round_id, new.user_id));
  return null;
end$$;

create or replace function public.push_freundschaft()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_wer text;
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    select username into v_wer from profiles where id = new.requester_id;
    perform public.push_anlegen(
      new.addressee_id, 'freunde',
      'Freundschaftsanfrage',
      format('%s möchte dich hinzufügen', coalesce(v_wer, 'Jemand')),
      jsonb_build_object('art', 'nachrichten', 'id', new.requester_id::text),
      format('freund-neu:%s:%s', new.requester_id, new.addressee_id));
    return null;
  end if;

  if tg_op = 'UPDATE' and new.status = 'accepted'
     and old.status is distinct from 'accepted' then
    select username into v_wer from profiles where id = new.addressee_id;
    perform public.push_anlegen(
      new.requester_id, 'freunde',
      'Freundschaft bestätigt',
      format('%s hat angenommen', coalesce(v_wer, 'Jemand')),
      jsonb_build_object('art', 'nachrichten', 'id', new.addressee_id::text),
      format('freund-ok:%s:%s', new.requester_id, new.addressee_id));
  end if;
  return null;
end$$;

-- ---------------------------------------------------------------------
-- 5) Offene Tipps: drei Stunden vor Anpfiff
-- ---------------------------------------------------------------------
-- Gemeldet wird ein Spiel, dessen Anstoß 150 bis 180 Minuten entfernt ist.
-- Der Lauf kommt alle 15 Minuten, jedes Spiel liegt also in zwei Läufen im
-- Fenster: Der erste meldet (genau drei Stunden oder bis zu 15 Minuten
-- darunter), der zweite fängt einen ausgefallenen ersten auf, und der
-- Schlüssel verhindert die Doppelung.
--
-- Gezählt werden nur Spiele **dieses** Anstoßes, und nur die ohne Tipp: Wer
-- alles getippt hat, hört nichts.
create or replace function public.push_tipp_erinnerungen()
returns int language plpgsql security definer set search_path = public as $$
declare r record; v_anzahl int := 0;
begin
  for r in
    select m.user_id,
           tr.id   as round_id,
           tr.name as runde,
           min(f.kickoff) as anstoss,
           count(*) as offen
      from tip_rounds tr
      join tip_round_members m on m.round_id = tr.id
      join fixtures f on f.league_id = tr.league_id
                     and f.season = tr.season
                     and f.status = 'scheduled'
                     and f.kickoff >  now() + interval '150 minutes'
                     and f.kickoff <= now() + interval '180 minutes'
     where not exists (select 1 from tips t
                        where t.round_id = tr.id
                          and t.user_id = m.user_id
                          and t.fixture_id = f.id)
     group by m.user_id, tr.id, tr.name
  loop
    if public.push_anlegen(
      r.user_id, 'tipps',
      'Noch nicht getippt',
      format('%s · Anpfiff %s Uhr, %s %s ohne deinen Tipp',
             r.runde,
             to_char(r.anstoss at time zone 'Europe/Berlin', 'HH24:MI'),
             r.offen,
             case when r.offen = 1 then 'Spiel' else 'Spiele' end),
      jsonb_build_object('art', 'tipprunde', 'id', r.round_id::text),
      format('tipps:%s:%s:%s', r.round_id, r.user_id,
             to_char(r.anstoss, 'YYYYMMDDHH24MI')))
    then
      v_anzahl := v_anzahl + 1;
    end if;
  end loop;
  return v_anzahl;
end$$;

-- ---------------------------------------------------------------------
-- 6) Live
-- ---------------------------------------------------------------------
-- Was von einem Spiel schon gemeldet ist: der letzte Sportmonks-Zustand
-- (`NS`, `INPLAY_1ST_HALF`, `HT`, `FT` …) und die IDs der gemeldeten
-- Ereignisse. Tore und Karten werden an ihrer Ereignis-ID erkannt, nicht am
-- Spielstand — ein korrigierter Stand (VAR, Nachtrag) löste sonst ein
-- zweites „Tor!" aus.
create table if not exists public.push_live_stand (
  fixture_id     text primary key,
  zustand        text not null,
  gemeldet       bigint[] not null default '{}',
  erstellt_at    timestamptz not null default now(),
  aktualisiert_at timestamptz not null default now()
);

-- Nur die Function liest und schreibt (Service-Role) — keine Policy.
alter table public.push_live_stand enable row level security;

-- Welche Spiele die Function abfragen soll: Anstoß zwischen vier Stunden
-- zurück (Pokal mit Verlängerung und Elfmeterschießen) und fünf Minuten
-- voraus, und noch nicht als beendet gesehen. Das Vorlaufende ist nötig: Nur
-- wer ein Spiel schon vor Anpfiff im Zustand `NS` kennt, kann den Anpfiff
-- melden (siehe Erstsicht unten).
--
-- Gibt es keinen einzigen Nutzer mit Lieblingsverein **und** Gerät, kommt
-- nichts zurück — dann kostet der Minutentakt keinen Sportmonks-Request.
create or replace function public.push_live_kandidaten()
returns setof text language sql stable security definer set search_path = public as $$
  select f.id
    from fixtures f
   where f.id like 'sportmonks:%'
     and f.kickoff between now() - interval '4 hours'
                       and now() + interval '5 minutes'
     and not exists (select 1 from push_live_stand s
                      where s.fixture_id = f.id
                        and s.zustand in ('FT', 'AET', 'FT_PEN', 'AWARDED',
                                          'WALKOVER', 'CANCELLED', 'ABANDONED'))
     and exists (select 1 from user_favorites u
                   join push_geraete g on g.user_id = u.user_id
                  where u.fav_type = 'team')
$$;

-- Eine Meldung an alle Fans der beiden Vereine.
create or replace function public.push_live_an_fans(
  p_spiel jsonb, p_kategorie text, p_titel text, p_text text, p_marke text
) returns int language plpgsql security definer set search_path = public as $$
declare r record; v_anzahl int := 0;
begin
  for r in select distinct user_id from user_favorites
            where fav_type = 'team'
              and key in (p_spiel->>'heim_key', p_spiel->>'gast_key') loop
    if public.push_anlegen(
      r.user_id, p_kategorie, p_titel, p_text,
      jsonb_build_object('art', 'spiel', 'id', p_spiel->>'fixture_id'),
      format('live:%s:%s:%s', p_spiel->>'fixture_id', p_marke, r.user_id))
    then
      v_anzahl := v_anzahl + 1;
    end if;
  end loop;
  return v_anzahl;
end$$;

-- Der Abgleich je Spiel. Erwartet (von `sync-live`):
--
--   { "fixture_id": "sportmonks:123", "zustand": "INPLAY_1ST_HALF",
--     "heim": "…", "gast": "…", "heim_key": "sportmonks:68", "gast_key": "…",
--     "tore_heim": 1, "tore_gast": 0,
--     "ereignisse": [ { "id": 99, "art": "tor"|"elfmeter"|"eigentor"|"rot"|"gelbrot",
--                      "minute": "23", "spieler": "…", "team": "…",
--                      "stand": "1:0" } ] }
--
-- **Erstsicht meldet nichts.** Taucht ein Spiel zum ersten Mal auf und läuft
-- schon (Function eben ausgespielt, Ausfall über den Anpfiff hinweg), wird
-- nur der Stand notiert. Sonst bekäme jeder Fan beim ersten Lauf alle Tore
-- der laufenden Spiele auf einmal.
create or replace function public.push_live_abgleich(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_alt     push_live_stand;
  v_zustand text := p->>'zustand';
  v_ids     bigint[];
  v_stand   text;
  v_ende    text[] := array['FT', 'AET', 'FT_PEN'];
  v_anzahl  int := 0;
  e         jsonb;
  v_titel   text;
  v_text    text;
begin
  if p->>'fixture_id' is null or v_zustand is null then return 0; end if;

  select coalesce(array_agg((x->>'id')::bigint), '{}')
    into v_ids
    from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x;

  select * into v_alt from push_live_stand
   where fixture_id = p->>'fixture_id' for update;

  if not found then
    insert into push_live_stand (fixture_id, zustand, gemeldet)
    values (p->>'fixture_id', v_zustand, v_ids)
    on conflict (fixture_id) do nothing;
    return 0;
  end if;

  v_stand := format('%s %s:%s %s', p->>'heim',
                    coalesce(p->>'tore_heim', '0'), coalesce(p->>'tore_gast', '0'),
                    p->>'gast');

  -- Anpfiff: aus `NS` (oder einem anderen Vorspiel-Zustand wie `DELAYED`)
  -- direkt in die erste Halbzeit.
  if v_zustand = 'INPLAY_1ST_HALF' and v_alt.zustand <> v_zustand
     and v_alt.zustand not in ('HT', 'INPLAY_2ND_HALF') then
    v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_anpfiff',
      'Anpfiff', format('%s – %s', p->>'heim', p->>'gast'), 'anpfiff');
  end if;

  -- Tore und Karten vor Halbzeit und Ende: Fällt ein Tor in der Minute vor
  -- dem Pfiff, steht es im selben Schnappschuss — und gehört davor.
  for e in select * from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb))
  loop
    continue when (e->>'id')::bigint = any (v_alt.gemeldet);

    if e->>'art' in ('tor', 'elfmeter', 'eigentor') then
      v_titel := format('Tor! %s %s %s', p->>'heim',
                        coalesce(e->>'stand', format('%s:%s',
                          coalesce(p->>'tore_heim', '0'), coalesce(p->>'tore_gast', '0'))),
                        p->>'gast');
      v_text := format('%s%s · %s.', coalesce(e->>'spieler', 'Tor'),
                       case e->>'art' when 'elfmeter' then ' (Elfmeter)'
                                      when 'eigentor' then ' (Eigentor)'
                                      else '' end,
                       coalesce(e->>'minute', '?'));
      v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_tore',
        v_titel, v_text, 'e' || (e->>'id'));
    elsif e->>'art' in ('rot', 'gelbrot') then
      v_titel := case e->>'art' when 'gelbrot' then 'Gelb-Rot' else 'Rote Karte' end;
      v_text := format('%s%s · %s. · %s', coalesce(e->>'spieler', 'Ein Spieler'),
                       case when e->>'team' is not null
                            then format(' (%s)', e->>'team') else '' end,
                       coalesce(e->>'minute', '?'), v_stand);
      v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_rote_karten',
        v_titel, v_text, 'e' || (e->>'id'));
    end if;
  end loop;

  if v_zustand = 'HT' and v_alt.zustand <> 'HT' then
    v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_halbzeit',
      'Halbzeit', v_stand, 'halbzeit');
  end if;

  if v_zustand = any (v_ende) and not (v_alt.zustand = any (v_ende)) then
    v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_endstand',
      'Abpfiff',
      v_stand || case v_zustand when 'AET' then ' n. V.'
                                when 'FT_PEN' then ' i. E.' else '' end,
      'ende');
  end if;

  update push_live_stand
     set zustand = v_zustand,
         gemeldet = (select coalesce(array_agg(distinct x), '{}')
                       from unnest(v_alt.gemeldet || v_ids) x),
         aktualisiert_at = now()
   where fixture_id = p->>'fixture_id';

  return v_anzahl;
end$$;

-- Aufräumen: Spiele, die länger als zwei Tage zurückliegen, braucht niemand.
create or replace function public.push_korb_aufraeumen()
returns void language sql security definer set search_path = public as $$
  delete from public.push_auftraege
   where gesendet_at is not null and gesendet_at < now() - interval '14 days';
  delete from public.push_live_stand
   where aktualisiert_at < now() - interval '2 days';
$$;

-- ---------------------------------------------------------------------
-- 7) Zeitplan
-- ---------------------------------------------------------------------
-- Header wie in 0129 (Begründung dort und in 0125).
do $$
declare
  v_key text := 'sb_publishable_lJBIlqeAYTILnQTInsK71Q_n2kCb7tN';
  v_url text := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/sync-live';
begin
  perform cron.schedule('sync-live', '* * * * *', format($cmd$
  select net.http_post(
    url := %L,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer %s',
      'x-sync-secret',
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'sync_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cmd$, v_url, v_key));
end $$;

-- ---------------------------------------------------------------------
-- 8) Rechte
-- ---------------------------------------------------------------------
-- Postgres gibt neuen Funktionen `execute` an `public`, Supabase zusätzlich an
-- `anon` und `authenticated`. Für alles, was Aufträge anlegt, ist das ein
-- offenes Tor: Ein Aufruf von `/rpc/push_anlegen` mit fremder `p_user` hätte
-- jedem Nutzer jeden Text aufs Handy gelegt. Aufrufen dürfen nur noch die
-- Trigger (laufen als Eigentümer), der Cron (postgres) und die Edge Functions
-- (service_role). `push_geraet_melden` bleibt offen — das ruft die App.
revoke execute on function public.push_anlegen(uuid, text, text, text, jsonb, text)
  from public, anon, authenticated;
revoke execute on function public.push_tipp_erinnerungen() from public, anon, authenticated;
revoke execute on function public.push_korb_aufraeumen() from public, anon, authenticated;
revoke execute on function public.push_live_kandidaten() from public, anon, authenticated;
revoke execute on function public.push_live_an_fans(jsonb, text, text, text, text)
  from public, anon, authenticated;
revoke execute on function public.push_live_abgleich(jsonb) from public, anon, authenticated;

grant execute on function public.push_live_kandidaten() to service_role;
grant execute on function public.push_live_abgleich(jsonb) to service_role;

-- Der Auftrag vom 05.10.2026 (Ausfall) hängt seit fünf gescheiterten
-- Versuchen am APNs-Schlüssel und hält seinen Schlüssel belegt. Er ist
-- veraltet; die Function gibt solche Aufträge ab jetzt selbst auf.
update public.push_auftraege
   set gesendet_at = now(), fehler = 'aufgegeben: ' || coalesce(fehler, '')
 where gesendet_at is null and versuche >= 5;
