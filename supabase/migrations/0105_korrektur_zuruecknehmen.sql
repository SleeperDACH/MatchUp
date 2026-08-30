-- Die Korrektur an Konstantelias/Bornauw wird zurueckgenommen.
--
-- In 0104 hatte ich das 2:0 im Spiel Dortmund gegen HSV auf Giannis
-- Konstantelias umgeschrieben, gestuetzt auf einen Spielbericht. **Das war
-- falsch**: Der Treffer ist offiziell als Eigentor von Sebastiaan Bornauw
-- gewertet, und Sportmonks lag richtig.
--
-- Die Lehre ist die unangenehmere Haelfte der Lehre von 0104: Ein
-- Spielbericht in Prosa („Konstantelias erzielte das 2:0") ist keine
-- Wertungsquelle. Er beschreibt, wer den Ball ins Tor gebracht hat — nicht,
-- wem die Statistik das Tor zuschreibt. Fuer eine Korrektur an den Zahlen
-- braucht es eine Quelle, die dieselbe Frage beantwortet wie die, die
-- korrigiert werden soll.
--
-- **Der Mechanismus bleibt.** `stat_overrides` und der Trigger sind richtig
-- und nachgewiesen wirksam; nur diese drei Eintraege gehen wieder raus. Der
-- Detektor `stats_widersprueche` bleibt ebenfalls — dass Bornauw mit `goals: 1`
-- dasteht, obwohl der HSV kein Tor erzielt hat, ist weiterhin ein
-- Widerspruch, den man sehen soll.

delete from public.stat_overrides
 where season = 2026 and round = 1
   and player_id in ('sportmonks:37336765', 'sportmonks:4536574');

-- Bestand zurueckholen: der naechste Sync schreibt die Quellwerte, aber wir
-- warten nicht darauf.
update public.player_match_stats set updated_at = updated_at
 where season = 2026 and round = 1
   and player_id in ('sportmonks:37336765', 'sportmonks:4536574');
