-- Beitritte kamen nur nach einem App-Neustart an.
--
-- Gemeldet als Performance-Problem: „Wenn Leute der Liga beitreten oder der
-- Draft startet, muss man die App komplett schließen und neu öffnen." Es war
-- keins — es war eine fehlende Live-Verbindung, und zwar an zwei Stellen
-- gleichzeitig, weshalb es sich wie ein Hänger anfühlte:
--
--  1. **`fantasy_league_members` stand nicht in der Realtime-Publication.**
--     Zehn andere Fantasy-Tabellen schon (`fantasy_rosters`, `draft_picks`,
--     `fantasy_leagues` …) — ausgerechnet die Mitgliederliste nicht. Ein
--     Beitritt konnte gar nicht ankommen, egal wie der Client fragte.
--  2. Der Client las sie über einen `FutureProvider`, der einmal lädt und nie
--     wieder. Das ist im selben Commit umgestellt.
--
-- Beides musste fallen. Realtime allein hilft nichts, wenn niemand zuhört;
-- Zuhören hilft nichts, wenn nichts gesendet wird.
--
-- `tip_rounds` und `tip_round_members` bekommen es aus demselben Grund mit:
-- Dort ist „jemand tritt bei" derselbe Vorgang, und die Tipprunden-Mitglieder
-- hätten beim nächsten Hinsehen dieselbe Überraschung geliefert.
--
-- Die Tabellen haben `replica_identity = default`, also den Primärschlüssel —
-- das genügt für Insert/Update/Delete-Ereignisse. RLS gilt für Realtime
-- weiter: Wer die Zeile nicht lesen darf, bekommt auch das Ereignis nicht.

do $$
declare
  t text;
begin
  foreach t in array array[
    'fantasy_league_members', 'tip_rounds', 'tip_round_members'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public'
         and tablename = t
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end$$;
