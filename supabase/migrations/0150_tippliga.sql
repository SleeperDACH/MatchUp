-- Die MatchUp Tippliga: ein Tippspiel für alle, nur 1. Bundesliga.
--
-- Anlass (29.10.2026, auf Ansage): Wer sich allein anmeldet, findet keine
-- Runde, der er beitreten kann — gezählt 9 von 32 Konten in keiner Liga,
-- und es gab keine einzige öffentliche Tipprunde. Die Tippliga ist ab der
-- ersten Minute da.
--
-- Entscheidungen, die hier stehen:
-- * **Beitritt per Knopf, nicht automatisch.** In der Tabelle stehen nur
--   Leute, die wirklich tippen, und Erinnerungen bekommt nur, wer mitspielen
--   will. Die Runde selbst sieht jeder (`tippliga()`), Mitglied wird man mit
--   `tippliga_beitreten()`.
-- * **Kein Chat.** Fremde schreiben sich nicht; die App hat keine Melde- oder
--   Blockierfunktion. Die Policy lehnt Nachrichten ab, die App zeigt keinen
--   Chat-Reiter.
-- * **Nicht löschbar**, auch nicht vom Admin — eine Runde aller Nutzer hängt
--   nicht an einem Fehlgriff.
-- * Sonst ist sie eine gewöhnliche Tipprunde: Tippen, Wertung (4/3/2),
--   Tabelle, Erinnerungen und Verlassen laufen wie überall.
--
-- Je Saison eine (eindeutiger Index). Für 2027/28 legt man eine neue an;
-- `tippliga()` nimmt die jüngste.

alter table public.tip_rounds
  add column if not exists ist_global boolean not null default false;

create unique index if not exists tip_rounds_tippliga_je_saison
  on public.tip_rounds (season) where ist_global;

-- Die Runde 2026/27. Admin ist der Betreiber (SFV03); der Trigger
-- `tip_rounds_add_creator` macht ihn zum Mitglied.
insert into public.tip_rounds
  (name, league_id, league_ids, season, created_by, visibility, join_policy,
   ist_global)
select 'MatchUp Tippliga', 'bundesliga', array['bundesliga'], 2026, p.id,
       'public', 'open', true
  from public.profiles p
 where p.username = 'SFV03'
   and not exists (select 1 from public.tip_rounds
                    where ist_global and season = 2026);

-- Was der Startbildschirm braucht, auch ohne Mitgliedschaft: Die RLS auf
-- `tip_rounds` zeigt nur eigene Runden, und das soll für alle anderen so
-- bleiben — deshalb eine Funktion statt einer weiteren Policy.
create or replace function public.tippliga()
returns table (id uuid, name text, mitglied boolean, mitspieler integer)
language sql stable security definer set search_path = public as $$
  select tr.id, tr.name,
         exists (select 1 from tip_round_members m
                  where m.round_id = tr.id and m.user_id = auth.uid()),
         (select count(*)::int from tip_round_members m
           where m.round_id = tr.id)
    from tip_rounds tr
   where tr.ist_global
   order by tr.season desc
   limit 1
$$;

create or replace function public.tippliga_beitreten()
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_runde uuid;
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet'; end if;
  select id into v_runde from tip_rounds
   where ist_global order by season desc limit 1;
  if v_runde is null then raise exception 'Die Tippliga gibt es noch nicht'; end if;
  insert into tip_round_members (round_id, user_id)
    values (v_runde, auth.uid())
  on conflict do nothing;
  return v_runde;
end$$;

revoke execute on function public.tippliga() from public, anon;
revoke execute on function public.tippliga_beitreten() from public, anon;
grant execute on function public.tippliga() to authenticated;
grant execute on function public.tippliga_beitreten() to authenticated;

-- Kein Chat in der Tippliga.
drop policy if exists "Mitglieder schreiben im Liga-Chat"
  on public.tip_round_messages;
create policy "Mitglieder schreiben im Liga-Chat"
  on public.tip_round_messages for insert
  with check (
    is_round_member(round_id)
    and user_id = auth.uid()
    and not exists (select 1 from tip_rounds tr
                     where tr.id = round_id and tr.ist_global)
  );

-- Nicht löschbar.
drop policy if exists "Ersteller kann Tipprunde löschen" on public.tip_rounds;
create policy "Ersteller kann Tipprunde löschen"
  on public.tip_rounds for delete
  using (created_by = auth.uid() and not ist_global);
