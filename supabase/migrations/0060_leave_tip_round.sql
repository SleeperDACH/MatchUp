-- Ein Mitglied verlässt eine Tipprunde. tip_round_members hat bewusst keine
-- direkte DELETE-Policy (Beitritt läuft ebenfalls nur über eine RPC), daher
-- erledigt eine SECURITY-DEFINER-Funktion das Austreten.
--
-- Der Ersteller kann NICHT austreten (er löscht die Runde stattdessen bzw.
-- müsste sie zuerst übergeben) — das verhindert eine verwaiste Runde ohne
-- Admin. Beim Austritt werden die eigenen Tipps und Bonustipp-Antworten der
-- Runde mit entfernt, damit die Wertung sauber bleibt; der Chatverlauf bleibt.
create function public.leave_tip_round(p_round_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_creator uuid;
begin
  select created_by into v_creator from tip_rounds where id = p_round_id;
  if v_creator is null then
    raise exception 'Tipprunde nicht gefunden';
  end if;
  if v_creator = auth.uid() then
    raise exception 'Der Ersteller kann die Runde nicht verlassen — bitte löschen.';
  end if;

  delete from tips
    where round_id = p_round_id and user_id = auth.uid();
  delete from tip_bonus_answers
    where round_id = p_round_id and user_id = auth.uid();
  delete from tip_round_members
    where round_id = p_round_id and user_id = auth.uid();
end;
$$;
