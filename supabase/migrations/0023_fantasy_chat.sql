-- Ligainterner Chat für Fantasy-Ligen: eine Nachrichten-Tabelle je Liga.
-- Nur Mitglieder dürfen lesen und schreiben (RLS über is_fantasy_member),
-- jeder schreibt ausschließlich unter der eigenen User-ID. Für den Live-Chat
-- wird die Tabelle in die Realtime-Publication aufgenommen. Spiegelbild zum
-- Tippspiel-Chat (tip_round_messages, Migration 0012).

create table public.fantasy_league_messages (
  id         uuid primary key default gen_random_uuid(),
  league_id  uuid not null references public.fantasy_leagues (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index fantasy_league_messages_league_idx
  on public.fantasy_league_messages (league_id, created_at);

alter table public.fantasy_league_messages enable row level security;

create policy "Mitglieder lesen den Liga-Chat"
  on public.fantasy_league_messages for select
  using (public.is_fantasy_member(league_id));

create policy "Mitglieder schreiben im Liga-Chat"
  on public.fantasy_league_messages for insert
  with check (public.is_fantasy_member(league_id) and user_id = auth.uid());

-- Live-Chat: Postgres-Changes über Supabase Realtime an die Clients.
alter publication supabase_realtime add table public.fantasy_league_messages;
