-- Liga verlassen (für Teilnehmer, die nicht der Ersteller sind).
--
-- Der Ersteller kann eine Liga nur löschen (0015), nicht verlassen. Alle
-- anderen Mitglieder können aussteigen; dabei werden ihre ligagebundenen
-- Daten entfernt (Kader, Aufstellungen, Waiver-Anträge, Draft-Picks), da
-- diese nicht per Cascade an der Mitgliedschaft hängen. Während eines
-- laufenden Drafts ist das Verlassen gesperrt (würde die Snake-Reihenfolge
-- zerreißen).

create function public.leave_fantasy_league(p_league_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_created_by uuid; v_status text; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Nicht angemeldet'; end if;

  select created_by, draft_status into v_created_by, v_status
    from fantasy_leagues where id = p_league_id for update;
  if v_created_by is null then raise exception 'Liga nicht gefunden'; end if;
  if v_created_by = v_uid then
    raise exception 'Der Ersteller kann die Liga nicht verlassen — nur löschen';
  end if;
  if not exists (select 1 from fantasy_league_members
                 where league_id = p_league_id and user_id = v_uid) then
    raise exception 'Du bist kein Mitglied dieser Liga';
  end if;
  if v_status = 'drafting' then
    raise exception 'Während des laufenden Drafts kann die Liga nicht verlassen werden';
  end if;

  -- Eigene ligagebundene Daten entfernen (kein Cascade von der Mitgliedschaft).
  delete from fantasy_waiver_claims where league_id = p_league_id and manager_id = v_uid;
  delete from fantasy_lineups        where league_id = p_league_id and manager_id = v_uid;
  delete from fantasy_rosters        where league_id = p_league_id and manager_id = v_uid;
  delete from draft_picks            where league_id = p_league_id and manager_id = v_uid;
  delete from fantasy_league_members where league_id = p_league_id and user_id  = v_uid;
end$$;
