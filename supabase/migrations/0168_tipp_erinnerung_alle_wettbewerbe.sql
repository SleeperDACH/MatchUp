-- 0168: Tipp-Erinnerung für alle Wettbewerbe einer Tipprunde (league_ids,
-- 0053), nicht nur den ersten. Sonst unverändert gegenüber 0156.
-- Rollback: Funktion aus 0156 erneut einspielen.

CREATE OR REPLACE FUNCTION public.push_tipp_erinnerungen()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;
  v_anzahl int := 0;
  v_schluessel text;
  v_zeit text;
begin
  for r in
    with offen as (
      select m.user_id,
             tr.id   as round_id,
             tr.name as runde,
             z.minuten,
             f.kickoff,
             f.id    as fixture_id
        from tip_rounds tr
        join tip_round_members m on m.round_id = tr.id
        left join push_einstellungen e on e.user_id = m.user_id
        -- Standard: 2 Stunden und 30 Minuten (0137).
        cross join lateral unnest(coalesce(e.tipp_zeiten, array[120, 30]))
             as z(minuten)
        -- **Alle Wettbewerbe der Runde** (0168): vorher nur league_id, also
        -- keine Erinnerung an Pokalspiele in einer Runde „BL + Pokal".
        join fixtures f on f.league_id = any(
                             case when cardinality(tr.league_ids) > 0
                                  then tr.league_ids
                                  else array[tr.league_id] end)
                       and f.season = tr.season
                       and f.status = 'scheduled'
                       and f.kickoff >  now() + make_interval(mins => z.minuten - 20)
                       and f.kickoff <= now() + make_interval(mins => z.minuten)
       where not exists (select 1 from tips t
                          where t.round_id = tr.id
                            and t.user_id = m.user_id
                            and t.fixture_id = f.id)
    )
    select user_id,
           minuten,
           kickoff as anstoss,
           count(distinct fixture_id) as spiele,
           count(distinct round_id) as runden,
           min(round_id::text) as eine_runde,
           string_agg(distinct runde, ' · ' order by runde) as namen
      from offen
     group by user_id, minuten, kickoff
  loop
    v_zeit := to_char(r.anstoss, 'YYYYMMDDHH24MI');
    v_schluessel := format('tipps:%s:%s:%s', r.user_id, v_zeit, r.minuten);
    -- Auch versandte Aufträge zählen (0136), und die im alten Format.
    continue when exists (
      select 1 from push_auftraege
       where schluessel = v_schluessel
          or schluessel like format('tipps:%%:%s:%s:%s', r.user_id, v_zeit, r.minuten));
    -- **Wie die übrigen Meldungen** (0156, auf Ansage): oben die Auskunft
    -- mit den Einzelheiten in Klammern, unten in einer Zeile der Rahmen —
    -- wie „Tor Dortmund (Bellingham, 34.)" über „Bayern 0:1 Dortmund".
    if public.push_anlegen(
      r.user_id, 'tipps',
      format('Noch nicht getippt (%s %s, %s)',
             r.spiele,
             case when r.spiele = 1 then 'Spiel' else 'Spiele' end,
             to_char(r.anstoss at time zone 'Europe/Berlin', 'HH24:MI')),
      r.namen,
      case when r.runden = 1
           then jsonb_build_object('art', 'tipprunde', 'id', r.eine_runde)
           else null end,
      v_schluessel)
    then
      v_anzahl := v_anzahl + 1;
    end if;
  end loop;
  return v_anzahl;
end$function$;
