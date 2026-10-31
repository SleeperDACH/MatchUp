-- 0156: Meldungen in einer Form (31.10.2026, auf Ansage mit Screenshot:
-- „genau so aussehen wie bei den anderen Meldungen" und „bei
-- zurückgenommenen Toren braucht es den Torschützen nicht mehr").
--
-- * „Kein Tor Dortmund (34.)" statt „Kein Tor Dortmund (Jobe Bellingham,
--   34.)" — darunter weiter der Stand.
-- * Tipp-Erinnerung wie Tor und Anpfiff: Titel mit Einzelheiten in Klammern,
--   Text eine Zeile: „Noch nicht getippt (5 Spiele, 15:30)" über
--   „BuLi 26/27 · Knapp daneben". Vorher zwei Textzeilen.

CREATE OR REPLACE FUNCTION public.push_live_abgleich(p jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_alt     push_live_stand;
  v_zustand text := p->>'zustand';
  v_ids     bigint[];
  v_stand   text;
  v_ende    text[] := array['FT', 'AET', 'FT_PEN'];
  v_anzahl  int := 0;
  e         jsonb;
  v_titel   text;
  v_text    text;
  v_tore    jsonb;
  v_summe   int;
  v_var     boolean;
  k         text;
  g         jsonb;
begin
  if p->>'fixture_id' is null or v_zustand is null then return 0; end if;

  select coalesce(array_agg((x->>'id')::bigint), '{}')
    into v_ids
    from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x;

  select * into v_alt from push_live_stand
   where fixture_id = p->>'fixture_id' for update;

  if not found then
    insert into push_live_stand (fixture_id, zustand, gemeldet, torsumme)
    values (p->>'fixture_id', v_zustand, v_ids,
            coalesce((p->>'tore_heim')::int, 0) + coalesce((p->>'tore_gast')::int, 0))
    on conflict (fixture_id) do nothing;
    return 0;
  end if;

  v_tore := coalesce(v_alt.tore, '{}'::jsonb);
  v_summe := coalesce((p->>'tore_heim')::int, 0) + coalesce((p->>'tore_gast')::int, 0);

  v_stand := format('%s %s:%s %s', p->>'heim',
                    coalesce(p->>'tore_heim', '0'), coalesce(p->>'tore_gast', '0'),
                    p->>'gast');

  -- Anpfiff: aus `NS` (oder einem anderen Vorspiel-Zustand wie `DELAYED`)
  -- direkt in die erste Halbzeit.
  if v_zustand = 'INPLAY_1ST_HALF' and v_alt.zustand <> v_zustand
     and v_alt.zustand not in ('HT', 'INPLAY_2ND_HALF') then
    v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_anpfiff',
      'Anpfiff', format('%s – %s', p->>'heim', p->>'gast'), 'anpfiff');
  end if;

  -- Tore und Karten vor Halbzeit und Ende: Fällt ein Tor in der Minute vor
  -- dem Pfiff, steht es im selben Schnappschuss — und gehört davor.
  for e in select * from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb))
  loop
    continue when (e->>'id')::bigint = any (v_alt.gemeldet);

    if e->>'art' in ('tor', 'elfmeter', 'eigentor') then
      -- **Oben, wer getroffen hat; unten das Spiel** (27.10.2026, auf Ansage:
      -- „in den Klammern auch noch den Torschützen, unten dann das Spiel mit
      -- dem Ergebnis"). Beim Eigentor ohne „für …" — welchem Verein die Quelle
      -- es zuordnet, ist nicht sicher, und ein falscher Verein wäre schlimmer.
      v_titel := concat_ws(' ',
        case
          when e->>'art' = 'eigentor' then 'Eigentor!'
          when e->>'team' is not null then format('Tor %s', e->>'team')
          else 'Tor!'
        end,
        -- Ohne Torschütze und Minute keine leere Klammer.
        '(' || nullif(concat_ws(', ',
          e->>'spieler',
          case e->>'art' when 'elfmeter' then 'Elfmeter' end,
          (e->>'minute') || '.'), '') || ')');
      v_text := format('%s %s %s', p->>'heim',
                        coalesce(e->>'stand', format('%s:%s',
                          coalesce(p->>'tore_heim', '0'), coalesce(p->>'tore_gast', '0'))),
                        p->>'gast');
      v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_tore',
        v_titel, v_text, 'e' || (e->>'id'));
      -- Gemeldete Tore merken (0154) — fällt eins später weg, kommt
      -- „Kein Tor" hinterher.
      v_tore := v_tore || jsonb_build_object(e->>'id', jsonb_build_object(
        'spieler', e->>'spieler', 'team', e->>'team',
        'minute', e->>'minute', 'art', e->>'art'));
    elsif e->>'art' in ('rot', 'gelbrot') then
      v_titel := case e->>'art' when 'gelbrot' then 'Gelb-Rot' else 'Rote Karte' end;
      v_text := format('%s%s · %s. · %s', coalesce(e->>'spieler', 'Ein Spieler'),
                       case when e->>'team' is not null
                            then format(' (%s)', e->>'team') else '' end,
                       coalesce(e->>'minute', '?'), v_stand);
      v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_rote_karten',
        v_titel, v_text, 'e' || (e->>'id'));
    end if;
  end loop;

  -- **Tor zurückgenommen** (0154, 31.10.2026, auf Ansage: „wenn das Tor
  -- zurückgenommen wird, dann eine Nachricht, dass es nicht zählt").
  -- Sportmonks löscht das Tor-Ereignis nach einem VAR-Entscheid und legt ein
  -- VAR-Ereignis „Goal disallowed" an (nachgesehen an zehn Fällen seit dem
  -- 17.10.). Gemeldet wird nur, was wir selbst als Tor gemeldet haben, und
  -- nur mit Beleg: VAR-Ereignis im Schnappschuss **oder** weniger Tore als
  -- zuletzt. Ein Tor, das bloß kurz in der Antwort fehlt oder mit neuer ID
  -- zurückkommt, löst so nichts aus.
  v_var := exists (
    select 1 from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x
     where x->>'art' = 'tor_aberkannt');
  for k, g in select * from jsonb_each(v_tore) loop
    continue when k::bigint = any (v_ids);
    continue when not (v_var or (v_alt.torsumme is not null and v_summe < v_alt.torsumme));
    v_titel := concat_ws(' ',
      case when g->>'team' is not null and g->>'art' <> 'eigentor'
           then format('Kein Tor %s', g->>'team') else 'Kein Tor' end,
      -- Ohne Torschützen (0156, auf Ansage): nur noch die Minute.
      '(' || nullif((g->>'minute') || '.', '.') || ')');
    v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_tore',
      v_titel, v_stand, 'z' || k);
    v_tore := v_tore - k;
  end loop;

  if v_zustand = 'HT' and v_alt.zustand <> 'HT' then
    v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_halbzeit',
      'Halbzeit', v_stand, 'halbzeit');
  end if;

  if v_zustand = any (v_ende) and not (v_alt.zustand = any (v_ende)) then
    v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_endstand',
      'Abpfiff',
      v_stand || case v_zustand when 'AET' then ' n. V.'
                                when 'FT_PEN' then ' i. E.' else '' end,
      'ende');
  end if;

  update push_live_stand
     set zustand = v_zustand,
         gemeldet = (select coalesce(array_agg(distinct x), '{}')
                       from unnest(v_alt.gemeldet || v_ids) x),
         tore = v_tore,
         torsumme = v_summe,
         aktualisiert_at = now()
   where fixture_id = p->>'fixture_id';

  -- **Sofort versenden** (0148): Liegt ein neuer Auftrag im Korb, stößt der
  -- Abgleich den Versand selbst an, statt auf den nächsten Minutentakt von
  -- `push-versand` zu warten. pg_net schickt den Aufruf erst nach dem Commit,
  -- der Auftrag ist dann also da. Der Minutentakt bleibt als Netz.
  if v_anzahl > 0 then
    perform public.wache_anstossen('push-versand');
  end if;

  return v_anzahl;
end$function$;

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
