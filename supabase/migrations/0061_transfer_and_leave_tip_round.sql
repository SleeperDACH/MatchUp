-- Der Ersteller (Admin) verlässt eine Tipprunde und übergibt dabei die
-- Adminrechte an ein anderes Mitglied. Läuft atomar in einer Funktion:
-- erst created_by umsetzen, dann den alten Admin (jetzt normales Mitglied)
-- samt seiner Tipps und Bonustipp-Antworten entfernen. Der Chatverlauf bleibt.
--
-- Ergänzt leave_tip_round (0060), das für den Ersteller bewusst blockt.
create function public.transfer_and_leave_tip_round(
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

  -- Adminrechte übergeben.
  update tip_rounds set created_by = p_new_owner where id = p_round_id;

  -- Alten Admin (jetzt gewöhnliches Mitglied) entfernen, inkl. eigener Daten.
  delete from tips
    where round_id = p_round_id and user_id = auth.uid();
  delete from tip_bonus_answers
    where round_id = p_round_id and user_id = auth.uid();
  delete from tip_round_members
    where round_id = p_round_id and user_id = auth.uid();
end;
$$;
