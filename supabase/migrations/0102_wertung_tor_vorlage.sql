-- Tor 16 -> 15, Vorlage 12 -> 10.
--
-- Anlass: Der Sturm lag im gemessenen Spieltag bei 15,1 Punkten im Schnitt,
-- das Mittelfeld bei 13,7. Beide Werte werden gesenkt.
--
-- **Die Aenderung im Dart-Standard allein reicht nicht.** Bestehende Ligen
-- tragen die Wertung als JSONB in `fantasy_leagues.scoring`, und `toJson()`
-- schreibt `goal` und `assist` ausdruecklich hinein — sie wuerden also beim
-- alten Wert bleiben. `cleanSheet` und `passMilestones` stehen dagegen NICHT
-- in der JSONB; die beiden anderen Aenderungen dieses Zuges (Zu Null 4 fuers
-- Mittelfeld, Pass-Schwellen 30/45) greifen deshalb ueber den Standard von
-- selbst.
--
-- **Nur v2-Ligen werden angefasst.** Die aelteren tragen `version: null` und
-- das alte 6-Kategorien-Objekt (`assist: 3`); fuer die gibt
-- `FantasyScoringRules.fromJson` ohnehin die Standardwertung zurueck, ihre
-- Zahlen anzufassen waere wirkungslos und irrefuehrend.
--
-- **Rueckwirkend?** Ja, und das ist unvermeidlich: Punkte werden bei jeder
-- Anzeige neu gerechnet, nicht gespeichert. Ein bereits gewerteter Spieltag
-- sieht danach anders aus. Wer das nicht will, muss die Wertung zwischen den
-- Saisons aendern, nicht mitten in ihr.

update public.fantasy_leagues
   set scoring = scoring
                 || jsonb_build_object('goal', 15, 'assist', 10)
 where scoring->>'version' = '2'
   and (scoring->>'goal' is distinct from '15'
        or scoring->>'assist' is distinct from '10');
