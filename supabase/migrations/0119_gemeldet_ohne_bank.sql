-- Eine Aufstellung ohne Bank ist nicht gemeldet.
--
-- Aufraeumen nach einem eigenen Fehlstart: Die erste Fassung des Syncs (0118)
-- erkannte die gemeldete Aufstellung an Zeilen vom Typ 11 (Startelf). Gemessen
-- am 02.09.2026 traegt `lineups` die aber schon **zwei bis drei Tage vor
-- Anpfiff** — fuer zwoelf Mannschaften der Spieltage am 4. und 5.9., elf je
-- Mannschaft, **ohne eine einzige** Zeile vom Typ 12. Das ist keine Meldung,
-- das ist dieselbe Erwartung noch einmal.
--
-- Die Function erkennt sie jetzt an der **Bank**; damit entstehen solche
-- Zeilen nicht mehr. Stehengeblieben sind sie trotzdem an einer Stelle: Wo
-- Sportmonks in einem Lauf gar nichts liefert, laesst der Sync die alten
-- Zeilen absichtlich stehen (eine leere Antwort darf keine Elf wegraeumen) —
-- und damit auch die falsche Markierung.
--
-- Die Regel als Aufraeumung: Ohne Bank im selben Spiel ist `bestaetigt`
-- falsch. Sie ist idempotent und trifft nichts Richtiges.

update public.predicted_lineups pl
   set bestaetigt = false
 where pl.bestaetigt
   and not exists (
     select 1 from public.predicted_lineups b
      where b.fixture_id = pl.fixture_id
        and b.bank);
