-- Wer keinen Torwart hat, spielt mit zehn — die Position bleibt leer.
--
-- Gemeldet als „bei Lewins Aufstellung passt irgendetwas gar nicht". Der
-- Befund: Sein Kader hatte 14 Spieler und **keinen einzigen Torwart**. Jede
-- Formation dieser App verlangt genau einen; ohne ihn nimmt
-- `fantasy_set_lineup` gar keine Elf an, der Aufstellungs-Schirm steht
-- dauerhaft auf „Nicht gespeichert – die Elf ist noch nicht vollständig", und
-- der Manager geht ohne eigenes Zutun mit null Punkten in jeden Spieltag.
--
-- **Die Daten waren richtig, die Folge war es nicht.** Am 02.09.2026 um 19:33
-- hat der Abgangs-Lauf aus 0117 Michael Zetterer aus seinem Kader genommen.
-- Nachgeprüft bei der Quelle: Zetterer ist am 29.08.2026 zu Leeds United
-- gewechselt, Hugo Larsson am 01.09. zu Fulham — beide haben die Bundesliga
-- wirklich verlassen, der Prune hat korrekt gearbeitet. Nur war Zetterer
-- Lewins **einziger** Torwart.
--
-- **Entschieden (04.09.2026): Die Torwartposition bleibt leer, die anderen
-- zehn bleiben besetzt.** Der naheliegende Weg wäre gewesen, ihm einen freien
-- Torwart in den Kader zu setzen — das hätte für ihn eine Kaderentscheidung
-- getroffen, die ihm gehört. Eine leere Position kostet ihn die Punkte dieses
-- einen Platzes; ein aufgezwungener Spieler kostet ihn den Kaderplatz.
--
-- Die Ausnahme ist **eng**: Sie gilt nur, wenn im Kader wirklich kein Torwart
-- steht. Wer einen hat, muss ihn aufstellen — sonst wäre aus der Notlösung
-- eine frei wählbare Formation mit zehn Feldspielern geworden.

create or replace function public.fantasy_set_lineup(
  p_league_id uuid, p_round integer, p_player_ids text[]
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_season int; v_roster jsonb;
  v_gk int; v_def int; v_mid int; v_fwd int;
  v_gk_slots int; v_starters int;
  v_def_min int; v_def_max int; v_mid_min int; v_mid_max int;
  v_fwd_min int; v_fwd_max int;
  v_hat_torwart boolean;
  v_alt text[]; v_pid text; v_kick timestamptz; v_name text;
begin
  if not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  select season, roster into v_season, v_roster
    from fantasy_leagues where id = p_league_id;

  select player_ids into v_alt
    from fantasy_lineups
   where league_id = p_league_id and manager_id = auth.uid()
     and season = v_season and round = p_round;
  v_alt := coalesce(v_alt, array[]::text[]);

  -- Nur die Änderung prüfen: rein oder raus (siehe 0084).
  for v_pid in
    (select unnest(p_player_ids) except select unnest(v_alt))
    union
    (select unnest(v_alt) except select unnest(p_player_ids))
  loop
    v_kick := public.fantasy_spieler_anpfiff(v_season, p_round, v_pid);
    if v_kick is not null and now() >= v_kick then
      select name into v_name from players where id = v_pid;
      raise exception 'Zu spät für %: Sein Spiel läuft schon.',
        coalesce(v_name, v_pid);
    end if;
  end loop;

  if exists (
    select 1 from unnest(p_player_ids) pid
    where not exists (
      select 1 from fantasy_rosters r
      where r.league_id = p_league_id and r.manager_id = auth.uid()
        and r.player_id = pid)) then
    raise exception 'Aufstellung enthält Spieler außerhalb deines Kaders';
  end if;

  v_gk_slots := coalesce((v_roster->>'gk')::int, 1);
  v_starters := v_gk_slots
              + coalesce((v_roster->>'def')::int, 4)
              + coalesce((v_roster->>'mid')::int, 4)
              + coalesce((v_roster->>'fwd')::int, 2);
  v_def_min := coalesce((v_roster->>'defMin')::int, 3);
  v_def_max := coalesce((v_roster->>'defMax')::int, 5);
  v_mid_min := coalesce((v_roster->>'midMin')::int, 2);
  v_mid_max := coalesce((v_roster->>'midMax')::int, 5);
  v_fwd_min := coalesce((v_roster->>'fwdMin')::int, 1);
  v_fwd_max := coalesce((v_roster->>'fwdMax')::int, 4);

  -- **Der ganze Kern dieser Migration.** Hat der Manager überhaupt einen
  -- Torwart? Wenn nicht, schrumpfen die Torwartplätze auf null und die Elf
  -- auf zehn. Geprüft wird der **Kader**, nicht die eingereichte Liste —
  -- sonst könnte jeder seinen Torwart einfach weglassen.
  select not exists (
    select 1 from fantasy_rosters r
    join players p on p.id = r.player_id
    where r.league_id = p_league_id and r.manager_id = auth.uid()
      and p.position = 'gk'
  ) into v_hat_torwart;

  if v_hat_torwart then
    v_starters := v_starters - v_gk_slots;
    v_gk_slots := 0;
  end if;

  select count(*) filter (where p.position = 'gk'),
         count(*) filter (where p.position = 'def'),
         count(*) filter (where p.position = 'mid'),
         count(*) filter (where p.position = 'fwd')
    into v_gk, v_def, v_mid, v_fwd
    from players p where p.id = any(p_player_ids);

  if coalesce(array_length(p_player_ids, 1), 0) <> v_starters then
    raise exception 'Aufstellung braucht genau % Spieler', v_starters;
  end if;

  if v_gk <> v_gk_slots
   or v_def < v_def_min or v_def > v_def_max
   or v_mid < v_mid_min or v_mid > v_mid_max
   or v_fwd < v_fwd_min or v_fwd > v_fwd_max then
    raise exception 'Aufstellung verletzt die Formation (% TW / % ABW / % MF / % ST)',
      v_gk, v_def, v_mid, v_fwd;
  end if;

  -- Gekoppelte Regel, siehe 0086: 3-3-4 fällt weg, 4-2-4 bleibt.
  if v_fwd >= 4 and v_def < 4 then
    raise exception
      'Vier Stürmer nur mit mindestens vier Abwehrspielern (% ABW / % ST)',
      v_def, v_fwd;
  end if;

  insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
  values (p_league_id, auth.uid(), v_season, p_round, p_player_ids)
  on conflict (league_id, manager_id, season, round)
    do update set player_ids = excluded.player_ids, updated_at = now();
end$$;

-- Trägt für jeden Manager **ohne Torwart im Kader** die zehn Feldspieler der
-- laufenden Runde ein, sofern er noch keine Aufstellung hat.
--
-- **Warum der Server das überhaupt schreibt:** Die App schickt eine
-- unvollständige Elf gar nicht erst ab (`naechsterSpeicherSchritt` →
-- `unvollstaendig`). Die gelockerte Regel oben allein änderte für den
-- Betroffenen deshalb nichts — er käme bis zum nächsten Release nicht an eine
-- gespeicherte Elf. Der Client zieht mit; bis dahin trägt der Server ein.
--
-- Gewählt wird nach **Einsatzminuten dieser Saison**, dann nach Namen. Keine
-- Punktewertung: Die steht in Dart, und eine zweite Fassung davon in SQL wäre
-- genau die Doppelung, die in diesem Projekt schon dreimal auseinanderlief.
-- Minuten sind der ehrlichere Maßstab für „spielt überhaupt", und der Manager
-- kann jede Position selbst überschreiben.
create or replace function public.fantasy_zehn_ohne_torwart()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec    record;
  v_ids    text[];
  v_anzahl int := 0;
begin
  for v_rec in
    select l.id as league_id, l.season, l.roster, r.manager_id,
           public.fantasy_laufende_runde(l.season) as runde
    from fantasy_leagues l
    join fantasy_rosters r on r.league_id = l.id
    join players p on p.id = r.player_id
    where l.draft_status = 'done'
    group by l.id, l.season, l.roster, r.manager_id
    having count(*) filter (where p.position = 'gk') = 0
  loop
    continue when v_rec.runde is null;

    -- **Nur vor dem ersten Anpfiff der Runde.** Diese Funktion schreibt
    -- direkt in `fantasy_lineups` und geht damit an `fantasy_set_lineup`
    -- vorbei — also auch an dessen Sperre je Spieler (0084). Ohne diese
    -- Bedingung könnte sie mitten im Spieltag eine Elf eintragen und damit
    -- rückwirkend Punkte verschieben; genau der Fehler, der in 0113–0115
    -- schon einmal repariert werden musste. Läuft die Runde bereits, bleibt
    -- der Manager diesen Spieltag ohne Elf und stellt ab dem nächsten selbst.
    -- **Auf die Bundesliga eingegrenzt und auf `sportmonks:`**, wie jede
    -- Runden-Funktion seit 0107/0108. Ohne den Ligafilter sah der erste
    -- Entwurf Runde 2 *aller* Wettbewerbe — die 2. Liga stößt am selben
    -- Wochenende früher an, und die Bedingung war damit schon erfüllt, bevor
    -- in der Bundesliga ein Ball rollte.
    continue when exists (
      select 1 from fixtures f
      where f.league_id = 'bundesliga'
        and f.id like 'sportmonks:%'
        and f.season = v_rec.season
        and f.round = v_rec.runde
        and f.kickoff <= now()
    );

    -- Eine vorhandene Aufstellung wird nie überschrieben — auch keine
    -- unvollständige. Dieselbe Zusage wie in 0110.
    continue when exists (
      select 1 from fantasy_lineups
      where league_id = v_rec.league_id and manager_id = v_rec.manager_id
        and season = v_rec.season and round = v_rec.runde
    );

    select array_agg(x.player_id) into v_ids
    from (
      select r.player_id
      from fantasy_rosters r
      join players p on p.id = r.player_id
      left join lateral (
        select coalesce(sum(s.minutes), 0) as minuten
        from player_match_stats s
        where s.player_id = r.player_id and s.season = v_rec.season
      ) m on true
      where r.league_id = v_rec.league_id
        and r.manager_id = v_rec.manager_id
        and p.position = 'def'
      order by m.minuten desc, p.name
      limit coalesce((v_rec.roster->>'def')::int, 4)
    ) x;

    select v_ids || array_agg(x.player_id) into v_ids
    from (
      select r.player_id
      from fantasy_rosters r
      join players p on p.id = r.player_id
      left join lateral (
        select coalesce(sum(s.minutes), 0) as minuten
        from player_match_stats s
        where s.player_id = r.player_id and s.season = v_rec.season
      ) m on true
      where r.league_id = v_rec.league_id
        and r.manager_id = v_rec.manager_id
        and p.position = 'mid'
      order by m.minuten desc, p.name
      limit coalesce((v_rec.roster->>'mid')::int, 4)
    ) x;

    select v_ids || array_agg(x.player_id) into v_ids
    from (
      select r.player_id
      from fantasy_rosters r
      join players p on p.id = r.player_id
      left join lateral (
        select coalesce(sum(s.minutes), 0) as minuten
        from player_match_stats s
        where s.player_id = r.player_id and s.season = v_rec.season
      ) m on true
      where r.league_id = v_rec.league_id
        and r.manager_id = v_rec.manager_id
        and p.position = 'fwd'
      order by m.minuten desc, p.name
      limit coalesce((v_rec.roster->>'fwd')::int, 2)
    ) x;

    -- Reicht der Kader nicht einmal für die zehn Feldspieler, wird nichts
    -- eingetragen: Eine halbe Elf zu erfinden hilft niemandem, und eine
    -- gespeicherte Zeile verhindert später die richtige.
    continue when coalesce(array_length(v_ids, 1), 0) <>
      coalesce((v_rec.roster->>'def')::int, 4)
      + coalesce((v_rec.roster->>'mid')::int, 4)
      + coalesce((v_rec.roster->>'fwd')::int, 2);

    insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
    values (v_rec.league_id, v_rec.manager_id, v_rec.season, v_rec.runde, v_ids);

    v_anzahl := v_anzahl + 1;
  end loop;

  return v_anzahl;
end;
$$;

-- Alle zehn Minuten, im selben Takt wie die Übernahme aus 0110: Der Fall
-- entsteht, wenn ein Abgangs-Lauf einen Torwart aus einem Kader nimmt, und
-- der läuft täglich.
select cron.unschedule('fantasy-zehn-ohne-torwart')
where exists (select 1 from cron.job where jobname = 'fantasy-zehn-ohne-torwart');

select cron.schedule(
  'fantasy-zehn-ohne-torwart',
  '*/10 * * * *',
  $cron$ select public.fantasy_zehn_ohne_torwart(); $cron$
);
