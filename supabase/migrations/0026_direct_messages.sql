-- Ligaübergreifende Direktnachrichten (1:1) zwischen Nutzern.
--
-- Unabhängig von Ligen — erreichbar über das Profil. Ein Nutzer sieht nur
-- Nachrichten, an denen er als Absender oder Empfänger beteiligt ist (RLS).
-- Der Client streamt die eigenen Nachrichten (RLS-gefiltert) und gruppiert
-- sie zu Konversationen. Empfänger werden per öffentlicher Profil-Namenssuche
-- gefunden (profiles ist bereits öffentlich lesbar).

create table public.direct_messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  body         text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at   timestamptz not null default now(),
  check (sender_id <> recipient_id)
);

create index direct_messages_pair_idx
  on public.direct_messages (sender_id, recipient_id, created_at);
create index direct_messages_recipient_idx
  on public.direct_messages (recipient_id, created_at);

alter table public.direct_messages enable row level security;

create policy "Beteiligte lesen ihre Direktnachrichten"
  on public.direct_messages for select
  using (sender_id = auth.uid() or recipient_id = auth.uid());

create policy "Nur unter eigener ID senden"
  on public.direct_messages for insert
  with check (sender_id = auth.uid());

-- Live: neue Nachrichten (gesendet wie empfangen) erscheinen sofort.
alter publication supabase_realtime add table public.direct_messages;
