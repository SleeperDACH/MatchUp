-- Profil- und Liga-Bilder ("Beides kombiniert"): entweder ein hochgeladenes
-- Bild (URL im Storage) ODER Emoji + Hintergrundfarbe als Alternative/Fallback.
-- Ist nichts gesetzt, bleibt es beim bisherigen Verhalten (Initiale bzw. Icon).

-- 1) Spalten je Entität. Der sichtbare Verweis (die *_url/*_emoji/*_color-Spalte)
--    ist die Sicherheitsgrenze: geschrieben nur vom Eigentümer/Admin über die
--    bereits vorhandenen UPDATE-Policies (profiles: id = auth.uid();
--    fantasy_leagues/tip_rounds: created_by = auth.uid()).
alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists avatar_emoji text,
  add column if not exists avatar_color text;

alter table public.fantasy_leagues
  add column if not exists logo_url text,
  add column if not exists logo_emoji text,
  add column if not exists logo_color text;

alter table public.tip_rounds
  add column if not exists logo_url text,
  add column if not exists logo_emoji text,
  add column if not exists logo_color text;

-- 2) Storage-Bucket für die Uploads, öffentlich lesbar (Avatare/Logos sind
--    nicht geheim; Anzeige läuft über die öffentliche URL).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 3) Storage-RLS: jeder darf lesen; eingeloggte Nutzer dürfen in den Bucket
--    schreiben. Missbrauch ist unkritisch, weil ein hochgeladenes Bild erst
--    sichtbar wird, wenn der Eigentümer/Admin den Verweis in seiner Zeile
--    setzt (eigene UPDATE-Policy je Tabelle).
create policy "avatars public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatars authenticated insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars');

create policy "avatars authenticated update"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars');

create policy "avatars authenticated delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars');
