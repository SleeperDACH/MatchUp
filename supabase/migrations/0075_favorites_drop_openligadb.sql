-- Alt-Favoriten aus der OpenLigaDB-Zeit entfernen.
--
-- Team-Favoriten werden über die reine Team-ID aufgelöst (`sportmonks:503`
-- → `503`) und damit gegen Sportmonks abgefragt. Zeilen mit einem
-- `openligadb:`-Schlüssel treffen dort nichts: Spielplan und News bleiben
-- leer, während Wappen und Name aus der gespeicherten Zeile weiter im
-- Favoriten-Tab standen. Der Stern in der Favoritenauswahl konnte sie nicht
-- entfernen, weil er auf den heutigen `sportmonks:`-Schlüssel wirkt — also
-- auf eine andere Zeile. Ergebnis: ein Wappen, das sich nicht abwählen ließ.
--
-- Die Zeilen sind nicht reparierbar (die OpenLigaDB-ID lässt sich ohne
-- Zuordnungstabelle nicht in eine Sportmonks-ID übersetzen) und tragen keine
-- Information mehr — sie werden gelöscht. Wer den Verein weiter als Favorit
-- will, setzt den Stern neu; das schreibt dann einen gültigen Schlüssel.
delete from public.user_favorites
where fav_type = 'team'
  and key not like 'sportmonks:%';
