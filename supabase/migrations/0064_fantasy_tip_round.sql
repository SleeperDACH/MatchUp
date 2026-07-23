-- Ligainternes Tippspiel: eine Tipprunde wird an eine Fantasy-Liga gekoppelt;
-- ihre Mitglieder sind automatisch die (aktiven) Fantasy-Mitglieder. So spielt
-- dieselbe Gruppe Fantasy UND Tippspiel. Es gibt höchstens eine Tipprunde pro
-- Fantasy-Liga.

alter table public.tip_rounds
  add column fantasy_league_id uuid references public.fantasy_leagues (id)
    on delete cascade;

-- Höchstens eine gekoppelte Tipprunde je Fantasy-Liga.
create unique index tip_rounds_fantasy_league_uidx
  on public.tip_rounds (fantasy_league_id)
  where fantasy_league_id is not null;

-- Verknüpft eine (frisch erstellte) Tipprunde mit einer Fantasy-Liga und
-- übernimmt alle aktiven Fantasy-Mitglieder. Nur zulässig, wenn der Aufrufer
-- sowohl die Tipprunde erstellt hat als auch Admin der Fantasy-Liga ist.
create function public.link_fantasy_tip_round(
  p_round_id uuid,
  p_league_id uuid
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_round_creator uuid;
  v_league_admin uuid;
begin
  select created_by into v_round_creator from tip_rounds where id = p_round_id;
  if v_round_creator is null then raise exception 'Tipprunde nicht gefunden'; end if;
  if v_round_creator <> auth.uid() then
    raise exception 'Nur der Ersteller der Tipprunde darf sie koppeln.';
  end if;

  select created_by into v_league_admin from fantasy_leagues where id = p_league_id;
  if v_league_admin is null then raise exception 'Fantasy-Liga nicht gefunden'; end if;
  if v_league_admin <> auth.uid() then
    raise exception 'Nur der Admin der Fantasy-Liga kann das Tippspiel aktivieren.';
  end if;

  if exists (select 1 from tip_rounds where fantasy_league_id = p_league_id) then
    raise exception 'Für diese Liga gibt es bereits ein Tippspiel.';
  end if;

  update tip_rounds set fantasy_league_id = p_league_id where id = p_round_id;

  -- Alle aktiven Fantasy-Mitglieder übernehmen (Ersteller ist per Trigger
  -- bereits Mitglied).
  insert into tip_round_members (round_id, user_id)
    select p_round_id, m.user_id
      from fantasy_league_members m
     where m.league_id = p_league_id and not m.vacant and not m.pending
  on conflict do nothing;
end$$;

-- Hält die Mitgliedschaft synchron: wird jemand aktives Fantasy-Mitglied
-- (Beitritt oder Zuweisung aus verwaist/wartend), kommt er automatisch ins
-- gekoppelte Tippspiel. Austritte lassen wir bewusst stehen (Tipps bleiben).
create function public.fantasy_member_sync_tip()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_round uuid;
begin
  if NEW.vacant or NEW.pending then return NEW; end if;
  select id into v_round from tip_rounds where fantasy_league_id = NEW.league_id;
  if v_round is not null then
    insert into tip_round_members (round_id, user_id)
      values (v_round, NEW.user_id)
    on conflict do nothing;
  end if;
  return NEW;
end$$;

create trigger fantasy_member_sync_tip_trg
  after insert or update of vacant, pending on public.fantasy_league_members
  for each row execute function public.fantasy_member_sync_tip();
