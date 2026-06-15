-- Favoriten je Nutzer: Teams (Vereine/Länder) und Ligen. Hängen am Konto und
-- syncen über Geräte. Anzeige/Filter im Live-Tab, Auswahl im Profil.
create table public.user_favorites (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  fav_type   text not null check (fav_type in ('team', 'league')),
  key        text not null,            -- team.id bzw. league.id
  label      text not null,            -- Anzeigename (Team- bzw. Liganame)
  league_id  text,                     -- bei Teams: zugehörige Liga
  short_name text,                     -- bei Teams: Kürzel (für Chips)
  icon_url   text,                     -- bei Teams: Wappen/Flagge
  created_at timestamptz not null default now(),
  primary key (user_id, fav_type, key)
);

alter table public.user_favorites enable row level security;

create policy "Eigene Favoriten lesen"
  on public.user_favorites for select
  using (user_id = auth.uid());

create policy "Eigene Favoriten anlegen"
  on public.user_favorites for insert
  with check (user_id = auth.uid());

create policy "Eigene Favoriten ändern"
  on public.user_favorites for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Eigene Favoriten löschen"
  on public.user_favorites for delete
  using (user_id = auth.uid());
