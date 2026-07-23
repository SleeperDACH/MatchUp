-- Adminrechte an ein anderes Mitglied übergeben, ohne selbst auszutreten —
-- für Tippspiel und Fantasy. Nur der aktuelle Admin (created_by) darf das,
-- Ziel muss (aktives) Mitglied sein.

-- Tippspiel: neuer Admin muss Mitglied der Runde sein.
create function public.transfer_tip_round_ownership(
  p_round_id uuid,
  p_new_owner uuid
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_creator uuid;
begin
  select created_by into v_creator from tip_rounds where id = p_round_id;
  if v_creator is null then
    raise exception 'Tipprunde nicht gefunden';
  end if;
  if v_creator <> auth.uid() then
    raise exception 'Nur der Admin kann die Rechte übergeben.';
  end if;
  if p_new_owner = auth.uid() then
    raise exception 'Bitte ein anderes Mitglied als neuen Admin wählen.';
  end if;
  if not exists (
    select 1 from tip_round_members
    where round_id = p_round_id and user_id = p_new_owner
  ) then
    raise exception 'Der neue Admin muss Mitglied der Runde sein.';
  end if;
  update tip_rounds set created_by = p_new_owner where id = p_round_id;
end;
$$;

-- Fantasy: neuer Admin muss aktives Mitglied sein (nicht verwaist/wartend).
create function public.fantasy_transfer_ownership(
  p_league_id uuid,
  p_new_owner uuid
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid;
begin
  select created_by into v_created_by
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then
    raise exception 'Liga nicht gefunden';
  end if;
  if auth.uid() <> v_created_by then
    raise exception 'Nur der Admin kann die Rechte übergeben.';
  end if;
  if p_new_owner = v_created_by then
    raise exception 'Bitte ein anderes Mitglied als neuen Admin wählen.';
  end if;
  if not exists (
    select 1 from fantasy_league_members
    where league_id = p_league_id and user_id = p_new_owner
      and not vacant and not pending
  ) then
    raise exception 'Der neue Admin muss aktives Mitglied sein.';
  end if;
  update fantasy_leagues set created_by = p_new_owner where id = p_league_id;
end;
$$;
