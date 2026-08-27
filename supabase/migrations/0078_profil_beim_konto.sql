-- Jedes Konto bekommt sein Profil beim Anlegen — in der Datenbank, nicht im
-- Client.
--
-- Vorher legte `AuthRepository.signUp` beides in **zwei** Schritten an: erst
-- `auth.signUp`, dann `insert into profiles`. Schlug der zweite fehl — etwa
-- weil der gewünschte Nutzername vergeben war (23505) —, blieb ein Konto ohne
-- Profil stehen. Und weil `fantasy_league_members`, Chats und Freundschaften
-- per Fremdschlüssel auf `profiles` zeigen, war so ein Konto tot: Jeder
-- Liga-Beitritt scheiterte mit
--
--   insert or update on table "fantasy_league_members" violates foreign key
--   constraint "fantasy_league_members_user_id_fkey" (23503)
--
-- und der Startbildschirm grüßte mit „Willkommen" statt mit dem Namen. Am
-- 27.08.2026 waren drei von fünfundzwanzig Konten in diesem Zustand; einen Weg
-- zurück gab es nicht, weil der Nachhol-Pfad nur hinter Google und Apple lief.
--
-- Der Trigger schließt die Lücke an der Stelle, an der sie entsteht. Er hängt
-- an `auth.users` und ist damit unabhängig von App-Version, Anmeldeweg und
-- davon, ob der Client seinen zweiten Schritt überhaupt schafft.
--
-- **Der Client bleibt zuständig für den gewünschten Namen.** Er trägt ihn nach
-- der Registrierung per `update` ein; misslingt das, steht schon ein gültiger
-- Platzhalter da, und niemand sitzt fest.

-- ---------------------------------------------------------------------
-- Namensfindung — dieselben Regeln wie `username_vorschlag.dart`:
-- Reihenfolge full_name → name → preferred_username → Teil vor dem @,
-- Leerraum zusammengezogen, auf 24 Zeichen gekappt, mindestens 3, sonst
-- „Tipper". Bewusst eine bewusste Doppelung: Der Client braucht die Regel für
-- seinen Vorschlag im laufenden Betrieb, die Datenbank für die Garantie. Wer
-- eine ändert, ändert die andere mit.
-- ---------------------------------------------------------------------
create or replace function public.profil_namensbasis(
  p_meta jsonb, p_email text)
returns text
language sql immutable as $$
  with kandidaten as (
    select unnest(array[
      p_meta->>'full_name',
      p_meta->>'name',
      p_meta->>'preferred_username',
      split_part(coalesce(p_email, ''), '@', 1)
    ]) as roh
  ),
  sauber as (
    select left(btrim(regexp_replace(roh, '\s+', ' ', 'g')), 24) as name
    from kandidaten
    where roh is not null
  )
  select coalesce(
    (select btrim(name) from sauber where char_length(btrim(name)) >= 3 limit 1),
    'Tipper');
$$;

-- ---------------------------------------------------------------------
-- Trigger: Profil anlegen, Namenskollisionen durchzählen.
-- ---------------------------------------------------------------------
create or replace function public.profil_fuer_neues_konto()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_basis text := public.profil_namensbasis(new.raw_user_meta_data, new.email);
  v_name  text;
begin
  -- Zehn Versuche wie im Client: Der Zähler hängt am Namen, nicht am Zufall.
  for i in 1..10 loop
    v_name := case when i = 1 then v_basis
                   -- Die Basis weicht, nicht die Unterscheidung — sonst reißt
                   -- der 24-Zeichen-Check.
                   else left(v_basis, 24 - char_length(i::text)) || i::text end;
    begin
      insert into public.profiles (id, username) values (new.id, v_name);
      return new;
    exception
      when unique_violation then
        -- Steht das Profil schon (zweiter Trigger-Lauf), ist alles gut.
        if exists (select 1 from public.profiles where id = new.id) then
          return new;
        end if;
        -- sonst: Name vergeben, nächster Versuch
    end;
  end loop;

  -- Elfter „Michael Müller": Die Unterscheidung kommt aus der Konto-ID, die
  -- ist eindeutig. Eine Endlosschleife im Anmeldevorgang wäre das schlechtere
  -- Ende — und ein Konto ohne Profil erst recht.
  insert into public.profiles (id, username)
  values (new.id, left(v_basis, 15) || left(replace(new.id::text, '-', ''), 8))
  on conflict (id) do nothing;
  return new;
exception
  -- Ein Profil, das sich nicht anlegen lässt, darf die Registrierung nicht
  -- verhindern: Lieber ein Konto, das der Client nachheilt, als gar keins.
  when others then
    raise warning 'Profil für % konnte nicht angelegt werden: %', new.id, sqlerrm;
    return new;
end$$;

drop trigger if exists profil_beim_konto on auth.users;
create trigger profil_beim_konto
  after insert on auth.users
  for each row execute function public.profil_fuer_neues_konto();
