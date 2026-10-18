-- Tipp-Erinnerung: Stunden nur noch im 2-Stunden-Takt (auf Ansage,
-- 17.10.2026). Wählbar sind 30 Minuten, 1 Stunde und 2, 4, 6 … 24 Stunden.
-- Der Standard folgt: **2 Stunden und 30 Minuten** vorher (vorher 3 Std. und
-- 30 Min. — die 3 ist nicht mehr wählbar). Beim Einspielen hatte noch
-- niemand eigene Zeiten gespeichert; wer ungültige trüge, fiele auf den
-- Standard zurück.

update public.push_einstellungen
   set tipp_zeiten = null
 where tipp_zeiten is not null
   and not (tipp_zeiten <@ array[30, 60, 120, 240, 360, 480, 600, 720, 840,
                                 960, 1080, 1200, 1320, 1440]);

alter table public.push_einstellungen
  drop constraint if exists push_einstellungen_tipp_zeiten_erlaubt;
alter table public.push_einstellungen
  add constraint push_einstellungen_tipp_zeiten_erlaubt check (
    tipp_zeiten is null or (
      cardinality(tipp_zeiten) between 1 and 14
      and tipp_zeiten <@ array[30, 60, 120, 240, 360, 480, 600, 720, 840, 960,
        1080, 1200, 1320, 1440]
    )
  );

create or replace function public.push_tipp_erinnerungen()
returns int language plpgsql security definer set search_path = public as $$
declare r record; v_anzahl int := 0; v_schluessel text; v_wann text;
begin
  for r in
    select m.user_id,
           tr.id   as round_id,
           tr.name as runde,
           z.minuten,
           min(f.kickoff) as anstoss,
           count(*) as offen
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
     group by m.user_id, tr.id, tr.name, z.minuten
  loop
    v_schluessel := format('tipps:%s:%s:%s:%s', r.round_id, r.user_id,
                           to_char(r.anstoss, 'YYYYMMDDHH24MI'), r.minuten);
    -- Auch versandte Aufträge zählen (siehe 0136).
    continue when exists (select 1 from push_auftraege
                           where schluessel = v_schluessel);
    v_wann := case
      when r.minuten < 60 then format('in %s Minuten', r.minuten)
      when r.minuten = 60 then 'in einer Stunde'
      else format('in %s Stunden', r.minuten / 60)
    end;
    if public.push_anlegen(
      r.user_id, 'tipps',
      'Noch nicht getippt',
      format('%s · Anpfiff %s (%s Uhr), %s %s ohne deinen Tipp',
             r.runde, v_wann,
             to_char(r.anstoss at time zone 'Europe/Berlin', 'HH24:MI'),
             r.offen,
             case when r.offen = 1 then 'Spiel' else 'Spiele' end),
      jsonb_build_object('art', 'tipprunde', 'id', r.round_id::text),
      v_schluessel)
    then
      v_anzahl := v_anzahl + 1;
    end if;
  end loop;
  return v_anzahl;
end$$;

revoke execute on function public.push_tipp_erinnerungen()
  from public, anon, authenticated;
