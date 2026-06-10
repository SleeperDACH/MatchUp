-- Ergänzungen für die Client-Anbindung:
-- 1. Wer eine Tipprunde erstellt, wird automatisch Mitglied (Trigger,
--    security definer, weil tip_round_members keine Insert-Policy hat).
-- 2. Die Standings-View respektiert die RLS des Aufrufers
--    (security_invoker), damit nur Mitglieder die Rangliste ihrer
--    Runde sehen.

create function public.add_creator_as_member()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into tip_round_members (round_id, user_id)
  values (new.id, new.created_by)
  on conflict do nothing;
  return new;
end;
$$;

create trigger tip_rounds_add_creator
  after insert on public.tip_rounds
  for each row execute function public.add_creator_as_member();

alter view public.tip_round_standings set (security_invoker = on);
