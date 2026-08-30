-- Ein Waiver-Antrag geht auch, wenn das Spiel schon laeuft.
--
-- 0094 hat angepfiffene Spieler aus der Free Agency genommen — richtig, denn
-- der Direktzugang braechte nichts: Die Aufstellung ist fuer sie diesen
-- Spieltag ohnehin gesperrt (0084). Die Oberflaeche zeigte daraufhin ein
-- Symbol, das nur erklaerte, warum nichts geht. **Das war zu wenig.**
--
-- Der Antrag ist der richtige Weg: Er sagt „ich will ihn ab naechster Woche",
-- und genau dafuer gibt es ihn. Ihn zu verweigern hiess, den Nutzer zwei Tage
-- warten zu lassen, um dann dasselbe zu tun.
--
-- **Gefahrlos ist das, weil das Fenster zwischen den Spieltagen liegt:**
-- `fantasy_next_waiver_window` setzt die Abarbeitung auf zwei Tage vor dem
-- ersten Anpfiff der naechsten Runde. Ein waehrend eines laufenden Spiels
-- gestellter Antrag wird also erst nach dessen Abpfiff bearbeitet — es kann
-- niemand mitten im Spieltag aus einer laufenden Elf gezogen werden.

-- ---------------------------------------------------------------------------
-- Antrag stellen
-- ---------------------------------------------------------------------------
create or replace function public.fantasy_submit_waiver_claim(
  p_league_id uuid,
  p_add_player_id text,
  p_drop_player_id text default null,
  p_rank integer default 1)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_season int; v_locked boolean; v_id uuid;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;
  select season into v_season from fantasy_leagues where id = p_league_id;

  -- **Neu: nicht mehr nur Wire-Spieler.** Beantragbar ist, wer auf dem Wire
  -- liegt ODER wessen Spiel gerade laeuft (und der deshalb seit 0094 nicht
  -- direkt geholt werden kann). Wer frei und abholbar ist, braucht keinen
  -- Antrag — den nimmt man einfach.
  if exists (select 1 from fantasy_rosters
             where league_id = p_league_id and player_id = p_add_player_id) then
    raise exception 'Spieler ist bereits in einem Kader';
  end if;
  if not exists (select 1 from fantasy_waiver_players
                 where league_id = p_league_id and player_id = p_add_player_id
                   and clears_at > now())
     and not public.fantasy_spieler_laeuft(v_season, p_add_player_id) then
    raise exception 'Spieler ist frei – du kannst ihn direkt holen';
  end if;

  select public.fantasy_is_locked(birth_date, is_foreign_newcomer, v_season, now())
    into v_locked from players where id = p_add_player_id;
  if v_locked then
    raise exception 'Spieler ist gesperrt (U20/Neuzugang)';
  end if;

  if p_drop_player_id is not null and not exists (
       select 1 from fantasy_rosters
       where league_id = p_league_id and player_id = p_drop_player_id
         and manager_id = auth.uid()) then
    raise exception 'Abzugebender Spieler ist nicht in deinem Kader';
  end if;

  insert into fantasy_waiver_claims
    (league_id, manager_id, add_player_id, drop_player_id, rank)
  values
    (p_league_id, auth.uid(), p_add_player_id, p_drop_player_id, greatest(p_rank, 1))
  returning id into v_id;
  return v_id;
end$function$;

-- ---------------------------------------------------------------------------
-- Antrag abarbeiten
-- ---------------------------------------------------------------------------
-- Die Auswahl verlangte bisher, dass der Spieler **zum Zeitpunkt der
-- Abarbeitung** auf dem Wire liegt. Fuer einen Antrag auf einen angepfiffenen
-- Spieler waere das nie erfuellt: Zwei Tage spaeter ist er kein Wire-Fall,
-- sondern schlicht frei — der Antrag haette bis zum Schluss der Schleife
-- gewartet und waere dann als „anderweitig vergeben" verfallen, obwohl ihn
-- niemand hat.
--
-- Maßgeblich ist deshalb nur noch, ob der Spieler **frei** ist. Beantragen
-- kann man ohnehin nur, was die Funktion oben zulaesst; die Sperre gehoert an
-- den Eingang, nicht an die Abarbeitung.
create or replace function public.fantasy_process_waivers(p_league_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_claim   fantasy_waiver_claims%rowtype;
  v_roster  jsonb; v_squad int; v_have int; v_frees int;
  v_guard   int := 0;
begin
  perform public.fantasy_init_waiver_priority(p_league_id);
  select roster into v_roster from fantasy_leagues where id = p_league_id for update;
  v_squad := public.fantasy_squad_size(v_roster);

  loop
    v_guard := v_guard + 1;
    exit when v_guard > 10000;

    -- Bester gewaehrbarer Antrag: Manager-Prioritaet, dann eigener Rang,
    -- dann Eingangszeit. Maßgeblich ist, dass der Spieler noch frei ist.
    select c.* into v_claim
    from fantasy_waiver_claims c
    join fantasy_league_members m
      on m.league_id = c.league_id and m.user_id = c.manager_id
    where c.league_id = p_league_id and c.status = 'pending'
      and not exists (select 1 from fantasy_rosters r
                      where r.league_id = c.league_id and r.player_id = c.add_player_id)
    order by m.waiver_priority asc, c.rank asc, c.created_at asc
    limit 1;
    exit when not found;

    -- Wird ein gueltiger Drop mitgegeben, schafft er Platz.
    v_frees := 0;
    if v_claim.drop_player_id is not null and exists (
         select 1 from fantasy_rosters
         where league_id = p_league_id and player_id = v_claim.drop_player_id
           and manager_id = v_claim.manager_id) then
      v_frees := 1;
    end if;

    select count(*) into v_have from fantasy_rosters
      where league_id = p_league_id and manager_id = v_claim.manager_id;

    if v_have - v_frees >= v_squad then
      update fantasy_waiver_claims
        set status = 'invalid', reason = 'Kader voll – Drop nötig', processed_at = now()
        where id = v_claim.id;
      continue;
    end if;

    if v_frees = 1 then
      delete from fantasy_rosters
        where league_id = p_league_id and player_id = v_claim.drop_player_id
          and manager_id = v_claim.manager_id;
    end if;
    insert into fantasy_rosters (league_id, manager_id, player_id, acquired_via)
    values (p_league_id, v_claim.manager_id, v_claim.add_player_id, 'waiver');

    update fantasy_waiver_claims
      set status = 'won', processed_at = now() where id = v_claim.id;
    delete from fantasy_waiver_players
      where league_id = p_league_id and player_id = v_claim.add_player_id;

    -- Rolling: Gewinner ans Ende der Prioritaet.
    update fantasy_league_members
      set waiver_priority = (select coalesce(max(waiver_priority), 0) + 1
                             from fantasy_league_members where league_id = p_league_id)
      where league_id = p_league_id and user_id = v_claim.manager_id;
  end loop;

  -- Uebrige offene Antraege: Spieler ging an hoehere Prioritaet bzw. ist weg.
  update fantasy_waiver_claims
    set status = 'lost', reason = 'Spieler anderweitig vergeben', processed_at = now()
    where league_id = p_league_id and status = 'pending';

  -- Aufraeumen: abgelaufene Wire-Eintraege freigeben (= echte Free Agents).
  delete from fantasy_waiver_players
    where league_id = p_league_id and clears_at <= now();
end$function$;
