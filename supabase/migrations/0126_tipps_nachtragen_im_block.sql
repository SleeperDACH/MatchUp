-- **Nachgetragene Tipps werden einmal je Spieltag gespeichert, nicht einzeln.**
--
-- Gemeldet am 13.09.2026: „Wenn man im Tippspiel nachträgliche Tipps nachträgt,
-- muss man jedes einzelne speichern können. Das bitte so ändern, dass alle
-- nachgetragenen Tipps pro Spieltag dann einmal nur gespeichert werden müssen."
--
-- Der Nachtrag-Schirm hatte je Zeile einen eigenen Speichern-Knopf; für einen
-- Bundesliga-Spieltag waren das **neun** Knöpfe und neun Aufrufe. Zwei Dinge
-- daran waren schlecht, und nur das erste ist Bequemlichkeit:
--
-- * Neun Tipps einzeln abzuschicken heißt, dass der fünfte scheitern kann,
--   während vier schon stehen — ein halb nachgetragener Spieltag, den niemand
--   als solchen sieht.
-- * Jeder Aufruf prüft dieselben drei Dinge neu (Ersteller? Mitglied?
--   Spiel gespiegelt?). Einmal genügt.
--
-- `tip_admin_set_tips` nimmt deshalb ein JSON-Array und schreibt **alles oder
-- nichts**. `tip_admin_set_tip` bleibt unverändert stehen: Ein einzelner
-- Nachtrag ist damit weiter möglich, und die ältere App-Version ruft ihn noch.

create or replace function public.tip_admin_set_tips(
  p_round_id uuid,
  p_user uuid,
  p_tipps jsonb
)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_eintrag jsonb;
  v_fixture text;
  v_home int;
  v_away int;
  v_anzahl int := 0;
begin
  -- **Die Prüfungen stehen vor der Schleife**, nicht darin: Sie hängen an der
  -- Runde und am Mitglied, nicht am einzelnen Spiel.
  if not exists (select 1 from tip_rounds
                 where id = p_round_id and created_by = auth.uid()) then
    raise exception 'Nur der Ersteller darf Tipps nachtragen';
  end if;
  if not exists (select 1 from tip_round_members
                 where round_id = p_round_id and user_id = p_user) then
    raise exception 'Nutzer ist kein Mitglied dieser Tipprunde';
  end if;
  if jsonb_typeof(p_tipps) <> 'array' then
    raise exception 'Tipps müssen als Array kommen';
  end if;

  for v_eintrag in select * from jsonb_array_elements(p_tipps)
  loop
    v_fixture := v_eintrag ->> 'fixture_id';
    v_home := (v_eintrag ->> 'home')::int;
    v_away := (v_eintrag ->> 'away')::int;

    -- **Ein unbekanntes Spiel bricht den ganzen Block ab.** Die Alternative
    -- wäre, es zu überspringen — dann stünde am Ende „gespeichert", und ein
    -- Tipp fehlte trotzdem. Genau die Sorte stiller Teilerfolg, gegen die in
    -- diesem Projekt an einem Dutzend Stellen argumentiert wird.
    if not exists (select 1 from fixtures where id = v_fixture) then
      raise exception
        'Spiel % noch nicht gespiegelt — bitte den Spieltag kurz öffnen',
        v_fixture;
    end if;
    if v_home is null or v_away is null
       or v_home < 0 or v_home > 99 or v_away < 0 or v_away > 99 then
      raise exception 'Ungültiges Ergebnis für %', v_fixture;
    end if;

    insert into tips (round_id, user_id, fixture_id, home_goals, away_goals,
                      updated_at)
    values (p_round_id, p_user, v_fixture, v_home, v_away, now())
    on conflict (round_id, user_id, fixture_id)
      do update set home_goals = excluded.home_goals,
                    away_goals = excluded.away_goals,
                    updated_at = now();
    v_anzahl := v_anzahl + 1;
  end loop;

  return v_anzahl;
end $$;

comment on function public.tip_admin_set_tips(uuid, uuid, jsonb) is
  'Trägt mehrere Tipps eines Mitglieds in einem Rutsch nach — alles oder '
  'nichts. Ersetzt neun Einzelaufrufe je Bundesliga-Spieltag.';

revoke all on function public.tip_admin_set_tips(uuid, uuid, jsonb) from public;
grant execute on function public.tip_admin_set_tips(uuid, uuid, jsonb)
  to authenticated;
