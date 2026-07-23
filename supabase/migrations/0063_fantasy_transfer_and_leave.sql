-- Der Fantasy-Admin (Ersteller) verlässt die Liga und übergibt dabei die
-- Adminrechte an ein aktives Mitglied. Atomar: erst created_by umsetzen, dann
-- den alten Admin wie beim normalen Verlassen als verwaisten Slot hinterlassen
-- (_fantasy_vacate — Kader bleibt erhalten). Während eines laufenden Drafts
-- gesperrt, analog zu leave_fantasy_league (0028).
create function public.fantasy_transfer_and_leave(
  p_league_id uuid,
  p_new_owner uuid
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Nicht angemeldet'; end if;
  select created_by, draft_status into v_created_by, v_status
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if v_created_by <> v_uid then
    raise exception 'Nur der Admin kann die Rechte übergeben.';
  end if;
  if p_new_owner = v_uid then
    raise exception 'Bitte ein anderes Mitglied als neuen Admin wählen.';
  end if;
  if v_status = 'drafting' then
    raise exception 'Während des laufenden Drafts kann die Liga nicht verlassen werden';
  end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = p_new_owner
                   and not vacant and not pending) then
    raise exception 'Der neue Admin muss aktives Mitglied sein.';
  end if;

  update fantasy_leagues set created_by = p_new_owner where id = p_league_id;
  perform public._fantasy_vacate(p_league_id, v_uid);
end$$;
