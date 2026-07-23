-- Freundschaften zwischen Nutzern (ligaübergreifend).
--
-- Eine Zeile pro Anfrage: [requester_id] hat [addressee_id] angefragt.
-- status 'pending' = offene Anfrage, 'accepted' = befreundet. Freunde eines
-- Nutzers = akzeptierte Zeilen, in denen er requester ODER addressee ist.
-- Der Client streamt die eigenen Zeilen (RLS-gefiltert) und leitet daraus
-- Freunde, eingehende und ausgehende Anfragen ab. Profile sind bereits
-- öffentlich lesbar (Suche per Benutzername).

create table public.friendships (
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

create index friendships_addressee_idx
  on public.friendships (addressee_id, status);

alter table public.friendships enable row level security;

create policy "Beteiligte lesen ihre Freundschaften"
  on public.friendships for select
  using (requester_id = auth.uid() or addressee_id = auth.uid());

create policy "Nur selbst Anfragen stellen"
  on public.friendships for insert
  with check (requester_id = auth.uid());

-- Annehmen (status → accepted) darf nur der Angefragte.
create policy "Angefragter nimmt an"
  on public.friendships for update
  using (addressee_id = auth.uid())
  with check (addressee_id = auth.uid());

-- Ablehnen / zurückziehen / entfernen darf jeder der beiden Beteiligten.
create policy "Beteiligte entfernen Freundschaft"
  on public.friendships for delete
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- Live: neue Anfragen und Annahmen erscheinen sofort.
alter publication supabase_realtime add table public.friendships;
