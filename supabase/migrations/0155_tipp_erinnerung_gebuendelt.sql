-- 0155: Tipp-Erinnerung gebündelt über alle Tippspiele (31.10.2026, auf
-- Ansage: „nicht jedes einzeln, sondern eine gemeinsame"; gewählt: je
-- Anstoß, aber alle Tippspiele in einer Meldung).
--
-- Vorher eine Meldung je Tippspiel, Anstoßzeit und Erinnerungszeitpunkt.
-- Gemessen am Wochenende 23.–26.10.: ein Nutzer in drei Tippspielen bekam
-- 27 Erinnerungen, je Anstoß zweimal dieselbe Auskunft für zwei Runden.
-- Jetzt je Nutzer, Anstoß und Zeitpunkt **eine**:
--
--   Noch nicht getippt
--   Anpfiff in 2 Stunden (15:30 Uhr) · 5 Spiele ohne deinen Tipp
--   BuLi 26/27 · Knapp daneben
--
-- Gezählt werden **verschiedene Spiele** (dasselbe Spiel in zwei Runden ist
-- eines). Ein Tippspiel → Tipp öffnet seinen Tippen-Reiter wie bisher;
-- mehrere → ohne Ziel, die App öffnet auf dem Homescreen mit allen Runden.
--
-- Schlüssel ohne Runde: tipps:<user>:<anstoß>:<minuten>. Damit beim
-- Umstieg nichts doppelt kommt, zählen auch Aufträge im alten Format
-- (tipps:<runde>:<user>:<anstoß>:<minuten>) als schon gemeldet.

create or replace function public.push_tipp_erinnerungen()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
  v_anzahl int := 0;
  v_schluessel text;
  v_zeit text;
  v_wann text;
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
        join fixtures f on f.league_id = tr.league_id
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
    v_wann := case
      when r.minuten < 60 then format('in %s Minuten', r.minuten)
      when r.minuten = 60 then 'in einer Stunde'
      else format('in %s Stunden', r.minuten / 60)
    end;
    if public.push_anlegen(
      r.user_id, 'tipps',
      'Noch nicht getippt',
      format(E'Anpfiff %s (%s Uhr) · %s %s ohne deinen Tipp\n%s',
             v_wann,
             to_char(r.anstoss at time zone 'Europe/Berlin', 'HH24:MI'),
             r.spiele,
             case when r.spiele = 1 then 'Spiel' else 'Spiele' end,
             r.namen),
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
