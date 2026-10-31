-- 0154: Live-Push ohne Dreifachversand, und „Kein Tor" nach VAR
-- (31.10.2026, gemeldet: „der Anstoß kam dreimal pro Partie" und „wenn ein
-- Tor zurückgenommen wird, kommt keine Info").
--
-- 1. Dreifachversand. In push_auftraege stand jeder Auftrag genau einmal.
--    Seit 0148 stößt push_live_abgleich den Versand je Spiel an — beim
--    gemeinsamen Anpfiff von fünf Partien laufen fünf Versandläufe
--    gleichzeitig, jeder las dieselben offenen Aufträge und schickte sie.
--    push_auftraege_holen beansprucht Aufträge jetzt atomar
--    (for update skip locked, Spalte in_arbeit_seit); ein Lauf, der
--    abstürzt, gibt seine nach 2 Minuten wieder frei.
-- 2. „Kein Tor". push_live_stand merkt sich gemeldete Tore (tore) und die
--    Torsumme. Fällt ein gemeldetes Tor aus der Quelle und gibt es dafür
--    einen Beleg (VAR-Ereignis „Goal disallowed", art tor_aberkannt aus
--    sync-live, oder weniger Tore als zuletzt), geht „Kein Tor <Verein>
--    (<Spieler>, <Minute>.)" mit dem aktuellen Stand an die Fans.

alter table public.push_auftraege
  add column if not exists in_arbeit_seit timestamptz;

alter table public.push_live_stand
  add column if not exists tore jsonb not null default '{}'::jsonb,
  add column if not exists torsumme int;

create or replace function public.push_auftraege_holen(p_limit int, p_max int)
returns setof public.push_auftraege
language sql
security definer
set search_path to 'public'
as $$
  update push_auftraege a
     set in_arbeit_seit = now()
   where a.id in (
     select id from push_auftraege
      where gesendet_at is null
        and versuche < p_max
        and (in_arbeit_seit is null or in_arbeit_seit < now() - interval '2 minutes')
      order by erstellt_at
      limit p_limit
      for update skip locked)
  returning a.*;
$$;

revoke all on function public.push_auftraege_holen(int, int) from public, anon, authenticated;
grant execute on function public.push_auftraege_holen(int, int) to service_role;

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
      '(' || nullif(concat_ws(', ', g->>'spieler', (g->>'minute') || '.'), '') || ')');
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
