-- Das Globale Tippspiel lässt sich verlassen — von jedem (09.11.2026, auf
-- Ansage: „Würde gerne einbauen, dass man das Globale Tippspiel wieder
-- verlassen kann").
--
-- `leave_tip_round` (0060) sperrt den Ersteller aus: In einer gewöhnlichen
-- Runde bliebe sie sonst ohne Admin zurück, er soll sie übergeben oder
-- löschen. Beim Globalen Tippspiel greift diese Begründung nicht — es ist
-- nicht löschbar (0150), seine Wertung ist fest (0152), und `created_by`
-- bleibt als Betreiber stehen, auch wenn er selbst nicht mehr mittippt.
-- Die App bot dem Ersteller dort deshalb nur „Adminrechte übergeben und
-- austreten" an, also die Runde aller Nutzer an einen Zufälligen.
--
-- Sonst unverändert: Tipps und Bonusantworten der Runde gehen mit, wie bei
-- jedem Austritt. Wieder mitspielen geht jederzeit über „Mitspielen" auf dem
-- Startbildschirm (`tippliga_beitreten`).
create or replace function public.leave_tip_round(p_round_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_creator uuid;
  v_global boolean;
begin
  select created_by, ist_global into v_creator, v_global
    from tip_rounds where id = p_round_id;
  if v_creator is null then
    raise exception 'Tipprunde nicht gefunden';
  end if;
  if v_creator = auth.uid() and not v_global then
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
