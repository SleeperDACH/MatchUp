-- Unentschieden bei knappem Ausgang: 5 bis 50 Punkte in Fünferschritten
-- (19.10.2026, auf Ansage). Vorher 1–20 in ganzen Punkten (0134).
--
-- Gefahrlos: Beim Einspielen hatte keine Liga die Regel eingeschaltet
-- (`remis_grenze is not null` → 0 Zeilen). Der Standard für neue Ligen (10)
-- steht in der App, nicht als Spaltenstandard — siehe 0135.

alter table public.fantasy_leagues
  drop constraint if exists fantasy_leagues_remis_grenze_bereich;

alter table public.fantasy_leagues
  add constraint fantasy_leagues_remis_grenze_bereich
  check (
    remis_grenze is null
    or (remis_grenze between 5 and 50 and mod(remis_grenze, 5) = 0)
  );
