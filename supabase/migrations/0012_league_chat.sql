-- Ligainterner Chat: eine Nachrichten-Tabelle je Tipprunde.
-- Nur Mitglieder dürfen lesen und schreiben (RLS über is_round_member),
-- jeder schreibt ausschließlich unter der eigenen User-ID. Für den
-- Live-Chat wird die Tabelle in die Realtime-Publication aufgenommen.

create table public.tip_round_messages (
  id         uuid primary key default gen_random_uuid(),
  round_id   uuid not null references public.tip_rounds (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index tip_round_messages_round_idx
  on public.tip_round_messages (round_id, created_at);

alter table public.tip_round_messages enable row level security;

create policy "Mitglieder lesen den Liga-Chat"
  on public.tip_round_messages for select
  using (public.is_round_member(round_id));

create policy "Mitglieder schreiben im Liga-Chat"
  on public.tip_round_messages for insert
  with check (public.is_round_member(round_id) and user_id = auth.uid());

-- Live-Chat: Postgres-Changes über Supabase Realtime an die Clients.
alter publication supabase_realtime add table public.tip_round_messages;
