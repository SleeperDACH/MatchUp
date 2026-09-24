-- Push-Benachrichtigungen: Geräte, Einstellungen, Ausgangskorb, Auslöser.
--
-- **Der Weg einer Benachrichtigung** — vier Stationen, und jede hat einen
-- Grund:
--
--   Ereignis (Trigger) → `push_auftraege` → Edge Function `push` → FCM
--
-- * **Trigger schreiben nur eine Zeile.** Kein `net.http_post` aus dem
--   Trigger heraus: Der Versand hinge sonst an der Transaktion, die ihn
--   ausgelöst hat — ein Pick würde langsamer, weil Google langsam antwortet,
--   und ein Fehler bei Google könnte einen Trade zurückrollen. Die Zeile im
--   Ausgangskorb ist billig und überlebt jeden Ausfall.
-- * **Der Cron leert den Korb** (jede Minute, siehe unten). Damit gilt
--   dieselbe Regel wie für die Sync-Functions: Die Function ist erst fertig,
--   wenn sie ausgespielt **und** eingeplant ist (`supabase functions list`,
--   `select * from cron.job`).
-- * **`push_anlegen` ist das einzige Tor.** Jeder Auslöser geht durch diese
--   Funktion, und dort stehen die drei Fragen, die man sonst siebenmal
--   beantworten müsste: Hat der Nutzer überhaupt ein Gerät? Will er diese
--   Sorte? Gibt es den Auftrag schon?
--
-- **Der Schlüssel gegen Doppelungen** (`schluessel`) ist wichtiger, als er
-- aussieht: Der Draft-Trigger feuert bei jedem Pick, und der Cron holt sich
-- offene Aufträge erneut, wenn der Versand scheitert. Ohne den eindeutigen
-- Index bekäme der Manager seinen „Du bist am Zug"-Hinweis zweimal.

-- ---------------------------------------------------------------------
-- 1) Geräte
-- ---------------------------------------------------------------------
-- Ein Nutzer hat mehrere Geräte, ein Gerät gehört zu genau einem Konto.
-- Meldet sich jemand anders auf demselben Gerät an, wandert der Token mit
-- (`on conflict (token) do update`) — sonst bekäme der Vorgänger die
-- Benachrichtigungen des Nachfolgers.
create table if not exists public.push_geraete (
  token      text primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  plattform  text not null check (plattform in ('ios', 'android', 'web')),
  erstellt_at timestamptz not null default now(),
  gesehen_at  timestamptz not null default now()
);

create index if not exists push_geraete_user_idx
  on public.push_geraete (user_id);

alter table public.push_geraete enable row level security;

drop policy if exists "Eigene Geräte lesen"
  on public.push_geraete;
create policy "Eigene Geräte lesen"
  on public.push_geraete for select using (user_id = auth.uid());
drop policy if exists "Eigenes Gerät eintragen"
  on public.push_geraete;
create policy "Eigenes Gerät eintragen"
  on public.push_geraete for insert with check (user_id = auth.uid());
drop policy if exists "Eigenes Gerät auffrischen"
  on public.push_geraete;
create policy "Eigenes Gerät auffrischen"
  on public.push_geraete for update using (user_id = auth.uid())
  with check (user_id = auth.uid());
drop policy if exists "Eigenes Gerät abmelden"
  on public.push_geraete;
create policy "Eigenes Gerät abmelden"
  on public.push_geraete for delete using (user_id = auth.uid());

-- **Den Token meldet eine Funktion, kein direktes Insert.** Wechselt auf
-- einem Gerät der Nutzer, gehört die Zeile noch dem Vorgänger — und eine
-- RLS-`update`-Policy prüft die **alte** Zeile. Der Nachfolger käme also
-- nicht an seinen eigenen Token heran, und zwar lautlos: Push bliebe für ihn
-- einfach aus. Deshalb übernimmt hier eine `security definer`-Funktion, die
-- den Token dem aktuell Angemeldeten zuschreibt.
create or replace function public.push_geraet_melden(
  p_token text,
  p_plattform text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet';
  end if;
  if p_plattform not in ('ios', 'android', 'web') then
    raise exception 'Unbekannte Plattform: %', p_plattform;
  end if;

  insert into public.push_geraete (token, user_id, plattform, gesehen_at)
  values (p_token, auth.uid(), p_plattform, now())
  on conflict (token) do update
    set user_id   = auth.uid(),
        plattform = excluded.plattform,
        gesehen_at = now();
end$$;

grant execute on function public.push_geraet_melden(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 2) Einstellungen je Nutzer
-- ---------------------------------------------------------------------
-- **Fehlende Zeile heißt „alles an".** Wer die App installiert und Push
-- erlaubt, hat damit gesagt, dass er Benachrichtigungen will; ihn danach
-- durch sieben Schalter zu schicken, wäre eine zweite Hürde für dieselbe
-- Entscheidung. Die Zeile entsteht erst, wenn er etwas abschaltet.
create table if not exists public.push_einstellungen (
  user_id      uuid primary key references public.profiles (id) on delete cascade,
  draft        boolean not null default true,
  trades       boolean not null default true,
  waiver       boolean not null default true,
  nachrichten  boolean not null default true,
  ausfaelle    boolean not null default true,
  tipps        boolean not null default true,
  anfragen     boolean not null default true,
  updated_at   timestamptz not null default now()
);

alter table public.push_einstellungen enable row level security;

drop policy if exists "Eigene Einstellungen lesen"
  on public.push_einstellungen;
create policy "Eigene Einstellungen lesen"
  on public.push_einstellungen for select using (user_id = auth.uid());
drop policy if exists "Eigene Einstellungen anlegen"
  on public.push_einstellungen;
create policy "Eigene Einstellungen anlegen"
  on public.push_einstellungen for insert with check (user_id = auth.uid());
drop policy if exists "Eigene Einstellungen ändern"
  on public.push_einstellungen;
create policy "Eigene Einstellungen ändern"
  on public.push_einstellungen for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3) Ausgangskorb
-- ---------------------------------------------------------------------
-- Keine RLS-Policy: Hier schreiben ausschließlich die Trigger (security
-- definer) und liest ausschließlich die Edge Function (Service-Role). Die
-- Zeile enthält den fertigen Text — was der Nutzer sieht, entsteht dort, wo
-- das Ereignis passiert, nicht im Versender.
create table if not exists public.push_auftraege (
  id          bigserial primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kategorie   text not null check (kategorie in
              ('draft','trades','waiver','nachrichten','ausfaelle','tipps','anfragen')),
  titel       text not null,
  text        text not null,
  -- Wohin das Antippen führt: {"art":"fantasy|tipprunde|nachrichten","id":"…"}.
  ziel        jsonb not null default '{}'::jsonb,
  schluessel  text,
  erstellt_at timestamptz not null default now(),
  gesendet_at timestamptz,
  versuche    int not null default 0,
  fehler      text
);

alter table public.push_auftraege enable row level security;

create index if not exists push_auftraege_offen_idx
  on public.push_auftraege (erstellt_at)
  where gesendet_at is null;

-- Ein offener Auftrag je Schlüssel. Gesendete zählen nicht mit: derselbe
-- Chat kann morgen wieder melden.
create unique index if not exists push_auftraege_schluessel_idx
  on public.push_auftraege (schluessel)
  where gesendet_at is null and schluessel is not null;

-- ---------------------------------------------------------------------
-- 4) Das einzige Tor: push_anlegen
-- ---------------------------------------------------------------------
-- Gibt zurueck, ob wirklich ein Auftrag entstanden ist — die Auslöser
-- ignorieren das (`perform`), der Erinnerungslauf zählt damit ehrlich.
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

  -- Ohne Gerät gibt es nichts zuzustellen. Spart dem Korb die Zeilen aller
  -- Nutzer, die Push nie erlaubt haben.
  if not exists (select 1 from push_geraete where user_id = p_user) then
    return false;
  end if;

  select case p_kategorie
           when 'draft'       then e.draft
           when 'trades'      then e.trades
           when 'waiver'      then e.waiver
           when 'nachrichten' then e.nachrichten
           when 'ausfaelle'   then e.ausfaelle
           when 'tipps'       then e.tipps
           when 'anfragen'    then e.anfragen
         end
    into v_an
    from push_einstellungen e
   where e.user_id = p_user;

  -- Keine Zeile = alles an (siehe oben).
  if v_an is not null and v_an = false then return false; end if;

  insert into push_auftraege (user_id, kategorie, titel, text, ziel, schluessel)
  values (p_user, p_kategorie, p_titel, p_text, coalesce(p_ziel, '{}'::jsonb),
          p_schluessel)
  on conflict do nothing
  returning id into v_id;

  return v_id is not null;
end$$;

-- ---------------------------------------------------------------------
-- 5) Auslöser
-- ---------------------------------------------------------------------

-- 5.1 Draft: wer am Zug ist, erfährt es.
--
-- **Der Trigger hängt an `fantasy_leagues`, nicht an `draft_picks`** — und
-- das ist kein Geschmack, sondern Reihenfolge: `fantasy_advance` (Migration
-- 0004) legt erst den Pick an und erhöht danach `picks_made`. Ein Trigger auf
-- `draft_picks` liefe also mit dem alten Zählerstand, und
-- `fantasy_current_manager` nennte den, der gerade gepickt hat.
--
-- Auf dem Zähler stimmt es, und der Draftbeginn ist gratis mit dabei: Beim
-- Start springt `draft_status` auf `drafting`, ohne dass ein Pick fällt.
create or replace function public.push_draft_am_zug()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_naechster uuid;
begin
  if new.draft_status <> 'drafting' then return null; end if;
  if new.picks_made is not distinct from old.picks_made
     and old.draft_status = 'drafting' then
    return null;
  end if;

  v_naechster := public.fantasy_current_manager(new.id);
  if v_naechster is null then return null; end if;

  perform public.push_anlegen(
    v_naechster, 'draft',
    'Du bist am Zug',
    format('%s · Pick %s', new.name, new.picks_made + 1),
    jsonb_build_object('art', 'fantasy', 'id', new.id::text),
    format('draft:%s:%s', new.id, new.picks_made + 1));
  return null;
end$$;

drop trigger if exists push_draft_am_zug_tr on public.fantasy_leagues;
create trigger push_draft_am_zug_tr
  after update of picks_made, draft_status on public.fantasy_leagues
  for each row execute function public.push_draft_am_zug();

-- 5.2 Trades: neues Angebot an den Empfänger, Entscheidung an den Anbieter.
create or replace function public.push_trade()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_liga text; v_von text; v_an text;
begin
  select name into v_liga from fantasy_leagues where id = new.league_id;

  if tg_op = 'INSERT' and new.status = 'pending' then
    select username into v_von from profiles where id = new.from_manager;
    perform public.push_anlegen(
      new.to_manager, 'trades',
      'Neues Trade-Angebot',
      format('%s bietet dir einen Trade an · %s', coalesce(v_von, 'Ein Manager'), v_liga),
      jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
      format('trade-neu:%s', new.id));
    return null;
  end if;

  if tg_op = 'UPDATE' and new.status is distinct from old.status
     and new.status in ('accepted', 'rejected') then
    select username into v_an from profiles where id = new.to_manager;
    perform public.push_anlegen(
      new.from_manager, 'trades',
      case new.status when 'accepted' then 'Trade angenommen'
                      else 'Trade abgelehnt' end,
      format('%s · %s', coalesce(v_an, 'Der Manager'), v_liga),
      jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
      format('trade-%s:%s', new.status, new.id));
  end if;
  return null;
end$$;

drop trigger if exists push_trade_tr on public.fantasy_trades;
create trigger push_trade_tr
  after insert or update of status on public.fantasy_trades
  for each row execute function public.push_trade();

-- 5.3 Waiver: durchgegangen oder nicht.
create or replace function public.push_waiver()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_spieler text; v_liga text;
begin
  if new.status is not distinct from old.status then return null; end if;
  if new.status not in ('won', 'lost', 'invalid') then return null; end if;

  select name into v_spieler from players where id = new.add_player_id;
  select name into v_liga from fantasy_leagues where id = new.league_id;

  perform public.push_anlegen(
    new.manager_id, 'waiver',
    case new.status when 'won' then 'Waiver durchgegangen'
                    else 'Waiver nicht durchgegangen' end,
    format('%s · %s', coalesce(v_spieler, 'Dein Antrag'), v_liga),
    jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
    format('waiver:%s', new.id));
  return null;
end$$;

drop trigger if exists push_waiver_tr on public.fantasy_waiver_claims;
create trigger push_waiver_tr
  after update of status on public.fantasy_waiver_claims
  for each row execute function public.push_waiver();

-- 5.4 Direktnachricht.
--
-- Der Schlüssel fasst zusammen, statt jede Nachricht einzeln zu melden: Wer
-- zehnmal hintereinander schreibt, löst **einen** offenen Auftrag aus. Ist er
-- schon versandt, darf der nächste kommen.
create or replace function public.push_direktnachricht()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_von text;
begin
  select username into v_von from profiles where id = new.sender_id;
  perform public.push_anlegen(
    new.recipient_id, 'nachrichten',
    coalesce(v_von, 'Neue Nachricht'),
    left(new.body, 140),
    jsonb_build_object('art', 'nachrichten', 'id', new.sender_id::text),
    format('dm:%s:%s', new.recipient_id, new.sender_id));
  return null;
end$$;

drop trigger if exists push_direktnachricht_tr on public.direct_messages;
create trigger push_direktnachricht_tr
  after insert on public.direct_messages
  for each row execute function public.push_direktnachricht();

-- 5.5 Liga-Chat (Fantasy) und Tipprunden-Chat: an alle außer den Absender.
create or replace function public.push_liga_chat()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_von text; v_liga text; r record;
begin
  select username into v_von from profiles where id = new.user_id;
  select name into v_liga from fantasy_leagues where id = new.league_id;
  for r in select user_id from fantasy_league_members
            where league_id = new.league_id and user_id <> new.user_id loop
    perform public.push_anlegen(
      r.user_id, 'nachrichten',
      format('%s · %s', coalesce(v_von, 'Neue Nachricht'), v_liga),
      left(new.body, 140),
      jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
      format('ligachat:%s:%s', new.league_id, r.user_id));
  end loop;
  return null;
end$$;

drop trigger if exists push_liga_chat_tr on public.fantasy_league_messages;
create trigger push_liga_chat_tr
  after insert on public.fantasy_league_messages
  for each row execute function public.push_liga_chat();

create or replace function public.push_runden_chat()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_von text; v_runde text; r record;
begin
  select username into v_von from profiles where id = new.user_id;
  select name into v_runde from tip_rounds where id = new.round_id;
  for r in select user_id from tip_round_members
            where round_id = new.round_id and user_id <> new.user_id loop
    perform public.push_anlegen(
      r.user_id, 'nachrichten',
      format('%s · %s', coalesce(v_von, 'Neue Nachricht'), v_runde),
      left(new.body, 140),
      jsonb_build_object('art', 'tipprunde', 'id', new.round_id::text),
      format('rundenchat:%s:%s', new.round_id, r.user_id));
  end loop;
  return null;
end$$;

drop trigger if exists push_runden_chat_tr on public.tip_round_messages;
create trigger push_runden_chat_tr
  after insert on public.tip_round_messages
  for each row execute function public.push_runden_chat();

-- 5.6 Aufgestellter Spieler fällt aus.
--
-- Gemeint ist die **zuletzt gespeicherte** Aufstellung je Manager, nicht
-- irgendeine aus der Saison: Ein Ausfall im September geht niemanden etwas
-- an, weil der Spieler im März einmal in der Elf stand.
create or replace function public.push_ausfall()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_spieler text; r record;
begin
  -- Abgelaufene Ausfälle (bis in der Vergangenheit) melden wir nicht.
  if new.bis is not null and new.bis < current_date then return null; end if;

  select name into v_spieler from players where id = new.player_id;

  for r in
    with letzte as (
      select distinct on (l.league_id, l.manager_id)
             l.manager_id, l.league_id, l.player_ids
        from fantasy_lineups l
       where l.season = (select max(season) from fantasy_lineups)
       order by l.league_id, l.manager_id, l.round desc
    )
    select * from letzte
  loop
    if new.player_id = any (r.player_ids) then
      perform public.push_anlegen(
        r.manager_id, 'ausfaelle',
        'Ausfall in deiner Elf',
        format('%s fällt aus (%s)', coalesce(v_spieler, 'Ein Spieler'),
               case new.kategorie when 'suspended' then 'Sperre' else 'Verletzung' end),
        jsonb_build_object('art', 'fantasy', 'id', r.league_id::text),
        format('ausfall:%s:%s', new.id, r.manager_id));
    end if;
  end loop;
  return null;
end$$;

drop trigger if exists push_ausfall_tr on public.player_absences;
create trigger push_ausfall_tr
  after insert on public.player_absences
  for each row execute function public.push_ausfall();

-- 5.7 Beitritts- und Freundschaftsanfragen.
create or replace function public.push_beitritt_fantasy()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_liga text; v_admin uuid; v_wer text;
begin
  select name, created_by into v_liga, v_admin
    from fantasy_leagues where id = new.league_id;
  select username into v_wer from profiles where id = new.user_id;
  perform public.push_anlegen(
    v_admin, 'anfragen',
    'Beitrittsanfrage',
    format('%s möchte in %s', coalesce(v_wer, 'Jemand'), v_liga),
    jsonb_build_object('art', 'fantasy', 'id', new.league_id::text),
    format('beitritt-f:%s:%s', new.league_id, new.user_id));
  return null;
end$$;

drop trigger if exists push_beitritt_fantasy_tr on public.fantasy_join_requests;
create trigger push_beitritt_fantasy_tr
  after insert on public.fantasy_join_requests
  for each row execute function public.push_beitritt_fantasy();

create or replace function public.push_beitritt_tipp()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_runde text; v_admin uuid; v_wer text;
begin
  select name, created_by into v_runde, v_admin
    from tip_rounds where id = new.round_id;
  select username into v_wer from profiles where id = new.user_id;
  perform public.push_anlegen(
    v_admin, 'anfragen',
    'Beitrittsanfrage',
    format('%s möchte in %s', coalesce(v_wer, 'Jemand'), v_runde),
    jsonb_build_object('art', 'tipprunde', 'id', new.round_id::text),
    format('beitritt-t:%s:%s', new.round_id, new.user_id));
  return null;
end$$;

drop trigger if exists push_beitritt_tipp_tr on public.tip_join_requests;
create trigger push_beitritt_tipp_tr
  after insert on public.tip_join_requests
  for each row execute function public.push_beitritt_tipp();

create or replace function public.push_freundschaft()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_wer text;
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    select username into v_wer from profiles where id = new.requester_id;
    perform public.push_anlegen(
      new.addressee_id, 'anfragen',
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
      new.requester_id, 'anfragen',
      'Freundschaft bestätigt',
      format('%s hat angenommen', coalesce(v_wer, 'Jemand')),
      jsonb_build_object('art', 'nachrichten', 'id', new.addressee_id::text),
      format('freund-ok:%s:%s', new.requester_id, new.addressee_id));
  end if;
  return null;
end$$;

drop trigger if exists push_freundschaft_tr on public.friendships;
create trigger push_freundschaft_tr
  after insert or update of status on public.friendships
  for each row execute function public.push_freundschaft();

-- ---------------------------------------------------------------------
-- 6) Offene Tipps kurz vor Anstoß (Cron, kein Trigger)
-- ---------------------------------------------------------------------
-- Es gibt kein Ereignis „Frist rückt näher" — das ist reine Zeit. Der Lauf
-- sucht Mitglieder, die ein Spiel des nächsten Anstoßes noch nicht getippt
-- haben, und meldet **einmal je Runde und Anstoßzeit** (Schlüssel).
--
-- Das Fenster ist bewusst breiter als der Takt (120 bis 60 Minuten vor
-- Anstoß bei einem Lauf alle 15 Minuten): Fällt ein Lauf aus, fängt der
-- nächste ihn auf, und der eindeutige Schlüssel verhindert die Doppelung.
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
                     and f.kickoff between now() + interval '60 minutes'
                                       and now() + interval '120 minutes'
     where not exists (select 1 from tips t
                        where t.round_id = tr.id
                          and t.user_id = m.user_id
                          and t.fixture_id = f.id)
     group by m.user_id, tr.id, tr.name
  loop
    if public.push_anlegen(
      r.user_id, 'tipps',
      'Tipps offen',
      format('%s · %s %s bis %s Uhr',
             r.runde, r.offen,
             case when r.offen = 1 then 'Spiel' else 'Spiele' end,
             to_char(r.anstoss at time zone 'Europe/Berlin', 'HH24:MI')),
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
-- 7) Zeitplan
-- ---------------------------------------------------------------------
-- Der Versand läuft im Minutentakt und ist billig, wenn nichts ansteht: Die
-- Function fragt zuerst den eigenen Korb und kehrt ohne einen einzigen
-- Google-Request um, wenn er leer ist — dieselbe Bauart wie `sync-stats`.
--
-- Der Authorization-Header steht hier aus dem Grund, den Migration 0125
-- ausführlich beschreibt: Ohne ihn weist das Gateway den Aufruf mit 401 ab,
-- sobald die Function einmal ohne `--no-verify-jwt` ausgespielt wurde — und
-- der Cron meldet trotzdem „succeeded".
do $$
declare
  v_key text := 'sb_publishable_lJBIlqeAYTILnQTInsK71Q_n2kCb7tN';
  v_url text := 'https://zleuiewcydrazogkfafp.supabase.co/functions/v1/push';
begin
  perform cron.schedule('push-versand', '* * * * *', format($cmd$
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

  perform cron.schedule('push-tipp-erinnerungen', '*/15 * * * *',
    'select public.push_tipp_erinnerungen();');
end $$;

-- ---------------------------------------------------------------------
-- 8) Aufräumen
-- ---------------------------------------------------------------------
-- Gesendete Aufträge sind Protokoll, kein Vorrat. Nach zwei Wochen weg.
create or replace function public.push_korb_aufraeumen()
returns void language sql security definer set search_path = public as $$
  delete from public.push_auftraege
   where gesendet_at is not null and gesendet_at < now() - interval '14 days';
$$;

select cron.schedule('push-korb-aufraeumen', '17 4 * * *',
  'select public.push_korb_aufraeumen();');
