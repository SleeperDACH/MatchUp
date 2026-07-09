-- Bonustipps (Saison-Prognosen) einer Tipprunde: pro Mitglied je Frage eine
-- Antwort (ein Team). Abgabe nur vor dem ersten Spieltag der Runde.

create table public.tip_bonus_answers (
  round_id   uuid not null references public.tip_rounds (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  question   text not null,          -- z. B. 'meister', 'absteiger', …
  team_id    text not null,          -- Provider-Team-ID (z. B. openligadb:40)
  team_name  text not null,
  updated_at timestamptz not null default now(),
  primary key (round_id, user_id, question)
);

alter table public.tip_bonus_answers enable row level security;

-- Abgabefenster offen? (vor dem ersten Anstoß der Liga/Saison der Runde).
-- Ohne gespiegelte Fixtures bleibt es offen.
create function public.tip_bonus_open(p_round_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select now() < min(f.kickoff)
       from public.fixtures f
       join public.tip_rounds r on r.id = p_round_id
      where f.league_id = r.league_id and f.season = r.season),
    true);
$$;

-- Mitglieder sehen alle Antworten der Runde.
create policy "Mitglieder sehen Bonustipps"
  on public.tip_bonus_answers for select
  using (public.is_round_member(round_id));

-- Nur eigene Antworten, nur als Mitglied, nur solange das Fenster offen ist.
create policy "Eigene Bonustipps anlegen"
  on public.tip_bonus_answers for insert
  with check (user_id = auth.uid()
              and public.is_round_member(round_id)
              and public.tip_bonus_open(round_id));

create policy "Eigene Bonustipps ändern"
  on public.tip_bonus_answers for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.tip_bonus_open(round_id));

create policy "Eigene Bonustipps löschen"
  on public.tip_bonus_answers for delete
  using (user_id = auth.uid() and public.tip_bonus_open(round_id));
