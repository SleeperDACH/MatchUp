-- Die Remis-Grenze hat keinen Spaltenstandard mehr.
--
-- 0134 setzte `default 5.0` für neue Ligen. Damit bekäme auch eine Liga, die
-- mit einer **älteren App-Version** angelegt wird (Store 1.7.1 kennt die
-- Regel nicht), still 5,0 — und diese Version zeigte dann Siege, wo die
-- neue App Unentschieden wertet. Die neue App schickt den Wert beim Anlegen
-- ausdrücklich mit (`FantasyLeague.remisGrenzeStandard`); alles andere bleibt
-- aus.
alter table public.fantasy_leagues
  alter column remis_grenze drop default;
