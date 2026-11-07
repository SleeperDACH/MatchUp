-- 0162: Torschützen-Verzögerung messen, 3. Liga und Frauen nur mit Minute
-- (06.11.2026, auf Ansage: „dann messen wir das über das Wochenende für 1. und
-- 2. Liga. Bei der 3. Liga und Frauen-BL reicht in der Benachrichtigung nur
-- die Minute").
--
-- live_tor_messung: je Tor, wann der Stand kam (stand_gesehen), wann das
-- passende Tor-Ereignis mit Torschützen (ereignis_gesehen), wann gemeldet
-- wurde und ob mit Namen. Auswertung:
--   select liga, count(*), percentile_cont(0.5) within group (order by
--          extract(epoch from ereignis_gesehen - stand_gesehen)) median_s, …
--     from live_tor_messung group by liga;
-- Läuft für alle Ligen mit; Kosten: eine Zeile je Tor.

create table if not exists public.live_tor_messung (
  fixture_id       text not null,
  liga             text,
  seite            text not null,
  nummer           int not null,
  stand            text not null,
  stand_gesehen    timestamptz not null,
  ereignis_gesehen timestamptz,
  gemeldet_at      timestamptz,
  mit_name         boolean,
  primary key (fixture_id, seite, nummer, stand)
);
alter table public.live_tor_messung enable row level security;
-- Keine Policies: nur der Server schreibt und liest.

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
  -- Tore (0157): je Seite ein Stapel gemeldeter Tore, dazu benutzte
  -- Ereignis-IDs und, je Seite, seit wann ein Tor ohne Ereignis wartet.
  v_tore    jsonb;
  v_seite   text;
  v_name    text;
  v_ist     int;
  v_stapel  jsonb;
  v_verw    jsonb;
  v_ev      jsonb;
  v_letzt   jsonb;
  v_init    boolean := false;
  -- 0162: Liga des Spiels (Name oder nur Minute) und Messung.
  v_liga    text;
  v_nur_minute boolean;
  v_stand_neu text;
begin
  if p->>'fixture_id' is null or v_zustand is null then return 0; end if;

  select coalesce(array_agg((x->>'id')::bigint), '{}')
    into v_ids
    from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x;

  select * into v_alt from push_live_stand
   where fixture_id = p->>'fixture_id' for update;

  if not found then
    insert into push_live_stand (fixture_id, zustand, gemeldet, tore)
    values (p->>'fixture_id', v_zustand, v_ids,
            public.push_live_tore_start(p))
    on conflict (fixture_id) do nothing;
    return 0;
  end if;

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

  -- **Tore folgen dem Spielstand, nicht der Ereignisliste** (0157,
  -- 31.10.2026, gemeldet an Bayern–Dortmund: „Tor Dortmund, nochmal Tor
  -- Dortmund, Kein Tor Dortmund — da stand es schon 1:0 für Bayern, wofür
  -- keine Nachricht kam"). Sportmonks hatte das Tor gelöscht und unter neuer
  -- ID wieder angelegt (zweite Meldung), und das Bayern-Tor stand schon im
  -- Stand, aber noch nicht in den Ereignissen (keine Meldung). Jetzt:
  -- * steigt der Stand einer Seite → „Tor"; Torschütze und Minute aus dem
  --   ältesten noch nicht benutzten Tor-Ereignis dieser Seite. Fehlt es,
  --   wird bis zu 45 s darauf gewartet, dann ohne Einzelheiten gemeldet.
  -- * sinkt er → „Kein Tor <Verein> (<Minute>.)" für das zuletzt gemeldete.
  -- * ein Tor, das nur mit neuer ID wiederkommt, ändert den Stand nicht.
  -- Die Seite kommt aus dem Stand — auch ein Eigentor landet beim richtigen
  -- Verein.
  select league_id into v_liga from fixtures where id = p->>'fixture_id';
  -- **3. Liga und Frauen-Bundesliga nur mit Minute** (0162, auf Ansage).
  v_nur_minute := coalesce(v_liga in ('liga3', 'frauen_bundesliga'), false);

  v_tore := v_alt.tore;
  if v_tore is null or not (v_tore ? 'heim') then
    -- Altbestand aus 0154 oder leer: still auf den aktuellen Stand setzen.
    v_tore := public.push_live_tore_start(p);
    v_init := true;
  end if;

  if not v_init then
    foreach v_seite in array array['heim', 'gast'] loop
      v_name := p->>v_seite;
      v_ist := coalesce((p->>('tore_' || v_seite))::int, 0);
      v_stapel := coalesce(v_tore->v_seite, '[]'::jsonb);
      v_verw := coalesce(v_tore->'verwendet', '[]'::jsonb);

      -- Neue Tore.
      while v_ist > jsonb_array_length(v_stapel) loop
        -- **Messung** (0162): Wann kam der Stand dieses Tors? Einmal je Tor.
        v_stand_neu := case v_seite
          when 'heim' then format('%s:%s', jsonb_array_length(v_stapel) + 1,
                                  coalesce((p->>'tore_gast')::int, 0))
          else format('%s:%s', coalesce((p->>'tore_heim')::int, 0),
                      jsonb_array_length(v_stapel) + 1) end;
        insert into live_tor_messung (fixture_id, liga, seite, nummer, stand, stand_gesehen)
        values (p->>'fixture_id', v_liga, v_seite, jsonb_array_length(v_stapel) + 1,
                v_stand_neu, now())
        on conflict (fixture_id, seite, nummer, stand) do nothing;
        -- **Neuestes** unbenutztes Tor-Ereignis dieser Seite: Ein Tor, das
        -- die Quelle unter neuer ID wieder anlegt, bleibt als älteres liegen
        -- und darf dem nächsten echten Tor nicht seinen Namen geben. Ein
        -- Eigentor (Zuordnung der Quelle unsicher) nur, wenn sonst keines
        -- passt.
        -- **Zuordnung über den Spielstand am Ereignis** (0161, 06.11.2026,
        -- gemeldet an Dresden–Fürth: 1:0 ohne Torschütze, das 2:0 mit dem
        -- Namen des 1:0, das 3:0 mit dem des 2:0). Die Quelle lieferte das
        -- Ereignis jeweils erst nach dem nächsten Stand; „neuestes
        -- unbenutztes" griff dann zum vorigen Tor. Jedes Tor-Ereignis trägt
        -- den Stand danach (`stand`, „2:0") — das k-te Tor einer Seite bekommt
        -- nur das Ereignis, dessen Zahl dieser Seite k ist. Gilt auch fürs
        -- Eigentor. Ohne Stand an den Ereignissen bleibt die alte Regel.
        select x into v_ev
          from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x
         where x->>'art' in ('tor', 'elfmeter', 'eigentor')
           and not v_verw ? (x->>'id')
           and coalesce(x->>'stand', '') ~ '^[0-9]+:[0-9]+$'
           and split_part(x->>'stand', ':',
                 case v_seite when 'heim' then 1 else 2 end)::int
               = jsonb_array_length(v_stapel) + 1
         limit 1;
        if v_ev is null and not exists (
          select 1 from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x
           where x->>'art' in ('tor', 'elfmeter', 'eigentor')
             and coalesce(x->>'stand', '') ~ '^[0-9]+:[0-9]+$') then
          select x into v_ev
            from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) with ordinality t(x, n)
           where x->>'art' in ('tor', 'elfmeter', 'eigentor')
             and not v_verw ? (x->>'id')
           order by (x->>'art' <> 'eigentor' and x->>'team' = v_name) desc,
                    (x->>'art' = 'eigentor') desc,
                    n desc
           limit 1;
          if v_ev is not null and v_ev->>'art' <> 'eigentor'
             and v_ev->>'team' is distinct from v_name then
            v_ev := null;  -- gehört der anderen Seite
          end if;
        end if;

        if v_ev is null then
          -- Noch kein Ereignis: höchstens 25 s warten.
          if v_tore->('wartet_' || v_seite) is null then
            v_tore := v_tore || jsonb_build_object('wartet_' || v_seite, now());
            exit;
          elsif (v_tore->>('wartet_' || v_seite))::timestamptz > now() - interval '45 seconds' then
            exit;
          end if;
        end if;

        -- **Ball statt Wort** (0158, auf Ansage: „Tor statt den Emoji").
        -- Die Seite kommt aus dem Stand, deshalb steht auch beim Eigentor
        -- der Verein, dem es zählt.
        -- Minute vorn, nur der Nachname (0159, auf Ansage):
        -- „⚽ Dortmund (34. Bellingham)".
        v_titel := concat_ws(' ',
          format('⚽ %s', v_name),
          '(' || nullif(concat_ws(', ',
            nullif(concat_ws(' ',
              (v_ev->>'minute') || '.',
              case when v_ev->>'art' = 'eigentor' then 'Eigentor' end,
              case when not v_nur_minute
                   then public.push_nachname(v_ev->>'spieler') end), ''),
            case v_ev->>'art' when 'elfmeter' then 'Elfmeter' end), '') || ')');
        v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_tore',
          v_titel, v_stand,
          format('tor:%s:%s:%s', v_seite, jsonb_array_length(v_stapel) + 1,
                 coalesce(v_ev->>'id', extract(epoch from now())::bigint::text)));
        update live_tor_messung
           set gemeldet_at = now(), mit_name = (v_ev is not null)
         where fixture_id = p->>'fixture_id' and seite = v_seite
           and nummer = jsonb_array_length(v_stapel) + 1
           and gemeldet_at is null;
        v_stapel := v_stapel || jsonb_build_array(jsonb_build_object(
          'spieler', v_ev->>'spieler', 'minute', v_ev->>'minute',
          'art', v_ev->>'art', 'id', v_ev->>'id'));
        if v_ev is not null then
          v_verw := v_verw || jsonb_build_array(v_ev->>'id');
        end if;
        v_tore := v_tore - ('wartet_' || v_seite);
      end loop;

      -- Aberkannte Tore.
      while v_ist < jsonb_array_length(v_stapel) loop
        v_letzt := v_stapel->-1;
        v_titel := concat_ws(' ',
          format('❌ VAR %s', v_name),
          '(' || nullif((v_letzt->>'minute') || '.', '.') || ')');
        v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_tore',
          v_titel, v_stand,
          format('kein:%s:%s:%s', v_seite, jsonb_array_length(v_stapel),
                 coalesce(v_letzt->>'id', extract(epoch from now())::bigint::text)));
        v_stapel := v_stapel - (jsonb_array_length(v_stapel) - 1);
        -- Was von dieser Seite noch als Tor-Ereignis herumliegt, ist
        -- überholt (das aberkannte Tor, auch unter neuer ID).
        v_verw := v_verw || coalesce((
          select jsonb_agg(x->>'id')
            from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x
           where x->>'art' in ('tor', 'elfmeter')
             and x->>'team' = v_name
             and not v_verw ? (x->>'id')), '[]'::jsonb);
      end loop;

      if v_ist = jsonb_array_length(v_stapel) then
        v_tore := v_tore - ('wartet_' || v_seite);
      end if;
      v_tore := v_tore || jsonb_build_object(v_seite, v_stapel, 'verwendet', v_verw);
    end loop;
  end if;

  -- **Messung** (0162): Wann kam der Torschütze? Erstes Auftauchen eines
  -- Tor-Ereignisses mit passendem Stand.
  update live_tor_messung m
     set ereignis_gesehen = now()
   where m.fixture_id = p->>'fixture_id'
     and m.ereignis_gesehen is null
     and exists (
       select 1 from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x
        where x->>'art' in ('tor', 'elfmeter', 'eigentor')
          and x->>'stand' = m.stand);

  -- Karten bleiben am Ereignis.
  for e in select * from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb))
  loop
    continue when (e->>'id')::bigint = any (v_alt.gemeldet);
    if e->>'art' in ('rot', 'gelbrot') then
      v_titel := case e->>'art' when 'gelbrot' then 'Gelb-Rot' else 'Rote Karte' end;
      v_text := format('%s%s · %s. · %s', coalesce(e->>'spieler', 'Ein Spieler'),
                       case when e->>'team' is not null
                            then format(' (%s)', e->>'team') else '' end,
                       coalesce(e->>'minute', '?'), v_stand);
      v_anzahl := v_anzahl + public.push_live_an_fans(p, 'live_rote_karten',
        v_titel, v_text, 'e' || (e->>'id'));
    end if;
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
         torsumme = coalesce((p->>'tore_heim')::int, 0) + coalesce((p->>'tore_gast')::int, 0),
         aktualisiert_at = now()
   where fixture_id = p->>'fixture_id';

  -- **Sofort versenden** (0148).
  if v_anzahl > 0 then
    perform public.wache_anstossen('push-versand');
  end if;

  return v_anzahl;
end$function$;
