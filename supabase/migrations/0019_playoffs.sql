-- Playoff-Einstellungen einer Fantasy-Liga.
--
-- * playoff_teams: Anzahl Teams in den Playoffs (ungerade -> Platz 1 Freilos).
-- * playoff_weeks: Dauer einer Playoff-Partie in Spieltagen (1 oder 2).
-- * trade_deadline_offset: Spieltage vor Playoff-Start für die Trade-Deadline
--   (5–10). Startspieltag & Deadline werden clientseitig aus der Saisonlänge
--   (34 Bundesliga-Spieltage) berechnet.
--
-- Alle null = noch nicht konfiguriert. Änderung nur vor dem Draft (Client +
-- RLS wie bei den übrigen Einstellungen).

alter table public.fantasy_leagues
  add column if not exists playoff_teams int,
  add column if not exists playoff_weeks smallint,
  add column if not exists trade_deadline_offset smallint;
