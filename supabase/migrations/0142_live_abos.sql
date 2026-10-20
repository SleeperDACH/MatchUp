-- **Live-Push für Vereine und ganze Ligen, unabhängig von den Favoriten**
-- (20.10.2026, auf Ansage).
--
-- Bis hierher bekam eine Live-Meldung nur, wer einen der beiden Vereine als
-- `user_favorites`-Team führt. Jetzt kommen zwei Wege dazu:
--
--   art = 'verein'  schluessel = 'sportmonks:<team-id>'  (wie user_favorites.key)
--   art = 'liga'    schluessel = 'bundesliga' | 'bundesliga2' | 'liga3'
--                                | 'frauen_bundesliga' | 'dfb_pokal'
--                                (wie fixtures.league_id)
--
-- Favoriten melden weiter wie bisher; ein Abo ist zusätzlich. Welche Sorten
-- (Anpfiff, Tore, …) ankommen, entscheiden für alle Wege dieselben Schalter
-- in `push_einstellungen`. Die Liga kommt aus `fixtures` über die
-- Fixture-ID — `sync-live` muss dafür nichts Neues schicken.

create table if not exists public.push_live_abos (
  user_id    uuid not null references auth.users(id) on delete cascade,
  art        text not null check (art in ('verein', 'liga')),
  schluessel text not null,
  angelegt_at timestamptz not null default now(),
  primary key (user_id, art, schluessel),
  constraint push_live_abos_liga_bekannt check (
    art <> 'liga' or schluessel in
      ('bundesliga', 'bundesliga2', 'liga3', 'frauen_bundesliga', 'dfb_pokal')),
  constraint push_live_abos_verein_form check (
    art <> 'verein' or schluessel like 'sportmonks:%')
);

alter table public.push_live_abos enable row level security;

drop policy if exists "Eigene Live-Abos lesen" on public.push_live_abos;
create policy "Eigene Live-Abos lesen" on public.push_live_abos
  for select using (user_id = auth.uid());
drop policy if exists "Eigene Live-Abos anlegen" on public.push_live_abos;
create policy "Eigene Live-Abos anlegen" on public.push_live_abos
  for insert with check (user_id = auth.uid());
drop policy if exists "Eigene Live-Abos löschen" on public.push_live_abos;
create policy "Eigene Live-Abos löschen" on public.push_live_abos
  for delete using (user_id = auth.uid());

create index if not exists push_live_abos_schluessel
  on public.push_live_abos (art, schluessel);

-- Empfänger: Fans (Favorit) ∪ Vereins-Abo ∪ Liga-Abo. `distinct`, damit ein
-- Nutzer mit Favorit und Liga-Abo nicht zweimal angelegt wird — der
-- Schlüssel verhinderte es ohnehin, aber ohne Umweg.
create or replace function public.push_live_an_fans(
  p_spiel jsonb, p_kategorie text, p_titel text, p_text text, p_marke text)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record; v_anzahl int := 0; v_liga text;
begin
  select league_id into v_liga from fixtures where id = p_spiel->>'fixture_id';

  for r in
    select user_id from user_favorites
     where fav_type = 'team'
       and key in (p_spiel->>'heim_key', p_spiel->>'gast_key')
    union
    select user_id from push_live_abos
     where art = 'verein'
       and schluessel in (p_spiel->>'heim_key', p_spiel->>'gast_key')
    union
    select user_id from push_live_abos
     where art = 'liga' and v_liga is not null and schluessel = v_liga
  loop
    if public.push_anlegen(
      r.user_id, p_kategorie, p_titel, p_text,
      jsonb_build_object('art', 'spiel', 'id', p_spiel->>'fixture_id'),
      format('live:%s:%s:%s', p_spiel->>'fixture_id', p_marke, r.user_id))
    then
      v_anzahl := v_anzahl + 1;
    end if;
  end loop;
  return v_anzahl;
end$function$;

revoke all on function public.push_live_an_fans(jsonb, text, text, text, text)
  from public, anon, authenticated;

-- Leerlauf bleibt gratis: Nur Spiele, für die es überhaupt einen Empfänger
-- mit Gerät gibt. Vorher genügte irgendein Favorit irgendwo.
create or replace function public.push_live_kandidaten()
 returns setof text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select f.id
    from fixtures f
   where f.id like 'sportmonks:%'
     and f.kickoff between now() - interval '4 hours'
                       and now() + interval '5 minutes'
     and not exists (select 1 from push_live_stand s
                      where s.fixture_id = f.id
                        and s.zustand in ('FT', 'AET', 'FT_PEN', 'AWARDED',
                                          'WALKOVER', 'CANCELLED', 'ABANDONED'))
     and (exists (select 1 from user_favorites u
                    join push_geraete g on g.user_id = u.user_id
                   where u.fav_type = 'team')
          or exists (select 1 from push_live_abos a
                       join push_geraete g on g.user_id = a.user_id))
$function$;

revoke all on function public.push_live_kandidaten() from public, anon, authenticated;
