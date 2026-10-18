-- Tipp-Erinnerungen individuell (auf Ansage, 17.10.2026).
--
-- Wer Tipp-Erinnerungen bekommt, wählt, **wann**: beliebig viele Zeitpunkte
-- aus 30 Minuten und 1 bis 24 Stunden vor Anpfiff (in Stunden-Schritten).
-- Gespeichert in Minuten. `null` heißt Standard: **3 Stunden und 30 Minuten**
-- vorher — vorher gab es nur die drei Stunden.
--
-- Und ein Fehler, der dabei auffiel: Der eindeutige Index auf `schluessel`
-- gilt nur für **offene** Aufträge (0129). Das Fenster war 30 Minuten breit,
-- der Lauf kam alle 15 — also lagen zwei Läufe darin, und war der erste
-- Auftrag schon versandt, legte der zweite denselben noch einmal an. Gezählt
-- am 17.10.2026: **56 von 58** Tipp-Erinnerungen gingen doppelt raus. Jetzt
-- prüft die Funktion jeden Schlüssel gegen alle Aufträge, auch versandte.

alter table public.push_einstellungen
  add column if not exists tipp_zeiten int[];

alter table public.push_einstellungen
  drop constraint if exists push_einstellungen_tipp_zeiten_erlaubt;
alter table public.push_einstellungen
  add constraint push_einstellungen_tipp_zeiten_erlaubt check (
    tipp_zeiten is null or (
      cardinality(tipp_zeiten) between 1 and 25
      and tipp_zeiten <@ array[30, 60, 120, 180, 240, 300, 360, 420, 480, 540,
        600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140, 1200, 1260, 1320,
        1380, 1440]
    )
  );

-- Gemeldet wird je gewähltem Zeitpunkt X ein Spiel, dessen Anstoß zwischen
-- X − 20 und X Minuten entfernt ist. Der Lauf kommt alle 5 Minuten; der erste
-- Lauf im Fenster meldet, die übrigen finden den Schlüssel schon vor.
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
      cross join lateral unnest(coalesce(e.tipp_zeiten, array[180, 30]))
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
    -- Auch versandte Aufträge zählen — siehe Kopf.
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

-- Takt: alle 5 statt 15 Minuten — eine Erinnerung „30 Minuten vorher" darf
-- nicht 15 Minuten zu früh oder zu spät kommen. Leerlauf kostet nur eine
-- Abfrage gegen die eigene Datenbank.
do $$
begin
  perform cron.unschedule('push-tipp-erinnerungen')
    where exists (select 1 from cron.job where jobname = 'push-tipp-erinnerungen');
  perform cron.schedule('push-tipp-erinnerungen', '*/5 * * * *',
    'select public.push_tipp_erinnerungen();');
end $$;
