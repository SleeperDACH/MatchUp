-- **Die Sync-Wache greift selbst ein — und sie klingelt.**
--
-- 0125 hat eine Wache gebaut, die ein Protokoll schreibt, und dazu notiert:
-- „Was offen bleibt: Es schaut niemand hin." Nachgesehen am 15.09.2026: Von
-- Freitag, 11.09., 21 Uhr bis Montag, 14.09., 15 Uhr stand in **jeder
-- einzelnen Stunde** mindestens ein `sync-stats`-Aufruf mit „Gateway Timeout"
-- im Protokoll — 67 Einträge über das ganze Spieltagswochenende. Gesehen hat
-- sie niemand.
--
-- Drei Dinge folgen daraus:
--
--   1. **Reparieren vor Melden.** Läuft ein Spiel ohne Punkte, stößt die Wache
--      `sync-fixtures` und `sync-stats` sofort selbst an. Gemeldet wird erst,
--      wenn das nach einer Wachrunde nichts gebracht hat.
--   2. **Ein Push aufs Handy** über ntfy.sh. Das Topic steht im Vault
--      (`ntfy_topic`), nicht hier: Wer es kennt, kann mitlesen.
--   3. **Zählen statt Stichprobe.** Die alte Wache schrieb je Stunde eine Zeile
--      und wusste nicht, ob dahinter ein Fehlschlag steckte oder sechzig. Ohne
--      diese Zahl lässt sich keine Schwelle setzen, und ohne Schwelle wird ein
--      Alarm im Minutentakt schnell ignoriert.

alter table public.sync_stoerungen
  add column if not exists gemeldet_am  timestamptz,
  add column if not exists angestossen_am timestamptz;

-- Der Bestand gilt als gemeldet. Sonst käme beim ersten Lauf ein Schwall von
-- siebzig Pushes für Vorfälle, die längst vorbei sind.
update public.sync_stoerungen
   set gemeldet_am = now()
 where gemeldet_am is null;


-- ---------------------------------------------------------------------------
-- Push
-- ---------------------------------------------------------------------------
create or replace function public.wache_push(
  p_titel      text,
  p_text       text,
  p_prioritaet int default 3
)
returns boolean
language plpgsql
security definer
set search_path = public, net, vault, pg_temp
as $$
declare
  v_topic text;
begin
  select decrypted_secret into v_topic
    from vault.decrypted_secrets
   where name = 'ntfy_topic'
   limit 1;
  -- Ohne Topic kein Push — und dann auch nicht als gemeldet markieren, damit
  -- der Vorfall nachgeholt wird, sobald das Topic steht.
  if v_topic is null then
    return false;
  end if;

  perform net.http_post(
    url := 'https://ntfy.sh/',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object(
      'topic', v_topic,
      'title', p_titel,
      'message', p_text,
      'priority', p_prioritaet
    ),
    timeout_milliseconds := 10000
  );
  return true;
end $$;


-- ---------------------------------------------------------------------------
-- Anstoßen
-- ---------------------------------------------------------------------------
-- Führt das Kommando des Cron-Jobs selbst aus, statt URL, Key und Secret hier
-- ein weiteres Mal aufzuschreiben — dieselbe Regel wie in 0125: Jede Kopie ist
-- eine Gelegenheit, dass eine beim nächsten Mal nicht mitgezogen wird.
create or replace function public.wache_anstossen(p_job text)
returns boolean
language plpgsql
security definer
set search_path = public, net, cron, vault, pg_temp
as $$
declare
  v_cmd text;
begin
  select command into v_cmd from cron.job where jobname = p_job;
  if v_cmd is null then
    return false;
  end if;
  execute v_cmd;
  return true;
end $$;


-- ---------------------------------------------------------------------------
-- Die Wache
-- ---------------------------------------------------------------------------
create or replace function public.pruefe_sync()
returns integer
language plpgsql
security definer
set search_path = public, net, cron, vault, pg_temp
as $$
declare
  v_neu    integer := 0;
  v_f      record;
  v_s      record;
  v_zeilen integer;
  v_push   boolean;
  v_titel  text;
  v_text   text;
  v_prio   int;
begin
  -- 1) **Läuft ein Spiel länger als 20 Minuten ohne eine einzige
  --    Statistikzeile für seine Runde?**
  --
  --    Die Saison kommt aus der Fixture-Zeile. 0125 rechnete sie aus dem Jahr
  --    des Anpfiffs — für die Rückrunde (Anpfiff 2027, Saison 2026) hätte die
  --    Wache ab Januar jedes Spiel als „ohne Punkte" gemeldet. Ohne Push fiel
  --    das nicht auf; mit Push wäre es ein Fehlalarm je Spiel.
  for v_f in
    select id, season, round, home_name, away_name, kickoff
      from public.fixtures
     where league_id = 'bundesliga'
       and id like 'sportmonks:%'
       and status = 'live'
       and kickoff < now() - interval '20 minutes'
  loop
    select count(*) into v_zeilen
      from public.player_match_stats
     where season = v_f.season
       and round = v_f.round;

    if v_zeilen = 0 then
      insert into public.sync_stoerungen (art, schluessel, details)
      values (
        'live_ohne_punkte',
        v_f.id,
        jsonb_build_object(
          'spiel', v_f.home_name || ' – ' || v_f.away_name,
          'runde', v_f.round,
          'anpfiff', v_f.kickoff
        )
      )
      on conflict (art, schluessel) do nothing;
      get diagnostics v_zeilen = row_count;

      if v_zeilen > 0 then
        v_neu := v_neu + 1;
        perform public.wache_anstossen('sync-fixtures');
        perform public.wache_anstossen('sync-stats');
        update public.sync_stoerungen
           set angestossen_am = now()
         where art = 'live_ohne_punkte' and schluessel = v_f.id;
      end if;
    end if;
  end loop;

  -- 2) **Antworten unserer eigenen Aufrufe außerhalb von 2xx — gezählt.**
  --    Eine Zeile je Stunde und Status; `hoechststand` ist die größte Zahl an
  --    Fehlschlägen, die eine Wachrunde im 15-Minuten-Fenster gesehen hat.
  --
  --    Ein Timeout hat keinen Statuscode. 0125 baute die Art als
  --    `'http_' || status_code` — bei `null` wird daraus `null`, die Spalte ist
  --    `not null`, und die ganze Wache bricht ab, genau dann, wenn sie etwas
  --    melden müsste.
  insert into public.sync_stoerungen (art, schluessel, details)
  select 'http_' || g.status,
         to_char(date_trunc('hour', now()), 'YYYY-MM-DD HH24') || ':' || g.status,
         jsonb_build_object(
           'status', g.status,
           'inhalt', g.inhalt,
           'zuletzt', g.zuletzt,
           'hoechststand', g.anzahl
         )
    from (
      select case
               when r.timed_out then 'timeout'
               else coalesce(r.status_code::text, 'fehler')
             end as status,
             count(*) as anzahl,
             max(r.created) as zuletzt,
             left(max(coalesce(r.content, r.error_msg, '')), 200) as inhalt
        from net._http_response r
       where r.created > now() - interval '15 minutes'
         and (r.timed_out
              or r.status_code is null
              or r.status_code < 200
              or r.status_code >= 300)
       group by 1
    ) g
  on conflict (art, schluessel) do update
     set details = public.sync_stoerungen.details
       || jsonb_build_object(
            'zuletzt', excluded.details -> 'zuletzt',
            'inhalt', excluded.details -> 'inhalt',
            'hoechststand', greatest(
              coalesce((public.sync_stoerungen.details ->> 'hoechststand')::int, 0),
              (excluded.details ->> 'hoechststand')::int
            )
          );

  -- 3) **Melden.** Einmal je Vorfall, und nur, was jemand tun muss.
  for v_s in
    select *
      from public.sync_stoerungen
     where gemeldet_am is null
       and erkannt_am > now() - interval '1 day'
     order by erkannt_am
  loop
    v_titel := null;

    if v_s.art = 'live_ohne_punkte' then
      -- Dem Anstoß eine Wachrunde Zeit geben.
      if v_s.angestossen_am > now() - interval '8 minutes' then
        continue;
      end if;
      select count(*) into v_zeilen
        from public.player_match_stats s
        join public.fixtures f on f.id = v_s.schluessel
       where s.season = f.season and s.round = f.round;
      if v_zeilen > 0 then
        -- Der Anstoß hat gereicht. Festhalten, nicht klingeln.
        update public.sync_stoerungen
           set gemeldet_am = now(),
               details = details || jsonb_build_object('behoben', 'durch Anstoß')
         where id = v_s.id;
        continue;
      end if;
      v_titel := 'MatchUp: Spiel läuft, keine Punkte';
      v_text := (v_s.details ->> 'spiel') || ' (Spieltag '
        || (v_s.details ->> 'runde') || ') hat seit über 20 Minuten keine '
        || 'Statistik. Sync wurde neu angestoßen, ohne Erfolg. '
        || 'Prüfen: select * from sync_wache;';
      v_prio := 5;

    elsif v_s.art like 'http_%' then
      -- Unter fünf Fehlschlägen in 15 Minuten fängt der Minutentakt das von
      -- selbst auf — die Zeile bleibt offen und kann noch über die Schwelle
      -- steigen, solange ihre Stunde läuft.
      if coalesce((v_s.details ->> 'hoechststand')::int, 0) < 5 then
        continue;
      end if;
      -- Ein anhaltender Ausfall ist **ein** Vorfall, nicht einer je Stunde.
      if exists (
        select 1 from public.sync_stoerungen o
         where o.art = v_s.art
           and o.id <> v_s.id
           and o.gemeldet_am > now() - interval '6 hours'
           and o.details ->> 'push' = 'true'
      ) then
        update public.sync_stoerungen
           set gemeldet_am = now(),
               details = details || jsonb_build_object('push', false)
         where id = v_s.id;
        continue;
      end if;
      v_titel := 'MatchUp: ' || (v_s.details ->> 'hoechststand')
        || ' Sync-Fehler (' || replace(v_s.art, 'http_', 'HTTP ') || ')';
      v_text := coalesce(nullif(v_s.details ->> 'inhalt', ''), 'ohne Antworttext')
        || ' — in 15 Minuten, zuletzt '
        || to_char((v_s.details ->> 'zuletzt')::timestamptz at time zone 'Europe/Berlin', 'DD.MM. HH24:MI')
        || '. Weitere Fehler dieser Art werden 6 Stunden lang nur protokolliert.';
      v_prio := 4;

    elsif v_s.art = 'tor_gekappt' then
      v_titel := 'MatchUp: Tor gedeckelt – ' || coalesce(v_s.details ->> 'spieler', '?');
      v_text := 'Spieltag ' || (v_s.details ->> 'runde') || ': Sportmonks-Statistik '
        || (v_s.details ->> 'laut_statistik') || ' Tor(e), Ereignisse '
        || (v_s.details ->> 'laut_ereignissen')
        || '. Gewertet wird die kleinere Zahl. Gegen den Spielbericht prüfen.';
      v_prio := 3;

    else
      -- Eine Art, die diese Wache nicht kennt, ist gerade deshalb zu melden.
      v_titel := 'MatchUp: Störung ' || v_s.art;
      v_text := left(v_s.details::text, 300);
      v_prio := 3;
    end if;

    v_push := public.wache_push(v_titel, v_text, v_prio);
    if v_push then
      update public.sync_stoerungen
         set gemeldet_am = now(),
             details = details || jsonb_build_object('push', true)
       where id = v_s.id;
    end if;
  end loop;

  return v_neu;
end $$;

comment on function public.pruefe_sync() is
  'Sync-Wache: erkennt „Spiel läuft, keine Punkte" und gehäufte Fehlantworten, '
  'stößt die Syncs selbst neu an und meldet per ntfy-Push (Topic im Vault), '
  'was sich so nicht beheben lässt. Alle 10 Minuten per pg_cron.';

-- **Nur der Cron darf das.** `security definer`-Funktionen sind in Postgres
-- standardmäßig für jeden ausführbar. Ein anonymer Aufruf von `pruefe_sync`
-- könnte seit dieser Migration Syncs anstoßen, einer von `wache_push` Pushes
-- verschicken.
revoke execute on function public.pruefe_sync() from public, anon, authenticated;
revoke execute on function public.wache_push(text, text, int) from public, anon, authenticated;
revoke execute on function public.wache_anstossen(text) from public, anon, authenticated;
