-- Live-Push schneller (27.10.2026, auf Ansage: „Die Benachrichtigung kommt
-- ziemlich spät nach dem Tor").
--
-- Gemessen: Zwei Minutentakte hintereinander. `sync-live` erkennt ein Tor
-- frühestens beim nächsten Lauf (im Mittel 30 s, höchstens 60 s), und
-- `push-versand` startet in derselben Sekunde — meist fertig, bevor der
-- Abgleich den Auftrag angelegt hat, und dann wartet der Auftrag eine weitere
-- Minute. Anpfiff und Abpfiff gingen genau 60 s nach dem Erkennen raus.
--
-- * `sync-live` alle 15 Sekunden (pg_cron ≥ 1.5 kann Sekunden). Kostet nur,
--   solange ein Spiel läuft: ein Sportmonks-Request je Lauf, gut 240 je
--   Stunde; ohne Kandidaten kehrt die Function ohne Request um.
-- * `push_live_abgleich` stößt den Versand selbst an, sobald etwas angelegt
--   wurde (`wache_anstossen`, 0127).
--
-- Was bleibt, ist die Zeit, bis die Quelle das Tor kennt.

select cron.alter_job(
  (select jobid from cron.job where jobname = 'sync-live'),
  schedule := '15 seconds'
);

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
begin
  if p->>'fixture_id' is null or v_zustand is null then return 0; end if;

  select coalesce(array_agg((x->>'id')::bigint), '{}')
    into v_ids
    from jsonb_array_elements(coalesce(p->'ereignisse', '[]'::jsonb)) x;

  select * into v_alt from push_live_stand
   where fixture_id = p->>'fixture_id' for update;

  if not found then
    insert into push_live_stand (fixture_id, zustand, gemeldet)
    values (p->>'fixture_id', v_zustand, v_ids)
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
          when e->>'team' is not null then format('Tor für %s', e->>'team')
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
