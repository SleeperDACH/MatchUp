-- Trade-Bewegungen kommen aus den Trade-Tabellen, nicht aus dem Kader.
--
-- Gemeldet an einem konkreten Fall: Nicolas Kristof ging erst von
-- hollmannleonard zu SFV03 (28.08. 17:58:47) und dann von SFV03 zu
-- julius_eggy (18:34:33). Im Protokoll stand hollmanns **Abgang auf 18:34:33**
-- — der Zeit des zweiten Trades —, und SFV03s Zugang um 17:58 fehlte ganz.
--
-- **Die Ursache steckt in der Rueckfuellung von 0097.** Sie haengte jede
-- Trade-Position an die vorhandene Zugangszeile desselben Spielers:
--
--     join fantasy_roster_moves z on z.player_id = it.player_id
--                                and z.richtung = 'zugang' and z.weg = 'trade'
--
-- Diese Zugangszeile stammt aber aus `fantasy_rosters` und kennt nur den
-- **aktuellen** Besitzer. Wer zweimal getradet wurde, hat dort genau einen
-- Eintrag — den letzten. Der erste Trade bekam damit den Zeitstempel des
-- zweiten verpasst, und der Zwischenbesitzer verschwand.
--
-- Solange ein Spieler nur einmal getauscht wird, faellt das nicht auf: Dann
-- ist die einzige Zugangszeile zufaellig die richtige. **Der Fehler wartet auf
-- den zweiten Tausch** — und genau der ist eingetreten.
--
-- Maßgeblich sind deshalb `fantasy_trades` und `fantasy_trade_items`. Sie
-- halten jeden Tausch vollstaendig fest: wer gibt, wer nimmt, und wann er
-- vollzogen wurde. Nachgezaehlt: alle sechs angenommenen Trades tragen
-- `executed_at`.

-- Erst alles Trade-Bezogene raeumen — es wird gleich vollstaendig und richtig
-- neu aufgebaut. Andere Wege (Draft, Free Agency, Waiver, Drops) bleiben
-- unberuehrt.
delete from public.fantasy_roster_moves where weg = 'trade';

-- Je Trade-Position zwei Bewegungen, beide auf der Zeit des Vollzugs:
-- der Abgeber verliert, die Gegenseite gewinnt.
insert into public.fantasy_roster_moves
  (league_id, manager_id, player_id, richtung, weg, passiert_am)
select t.league_id, it.giver, it.player_id, 'abgang', 'trade', t.executed_at
  from public.fantasy_trade_items it
  join public.fantasy_trades t on t.id = it.trade_id
 where t.status = 'accepted' and t.executed_at is not null
union all
select t.league_id,
       case when it.giver = t.from_manager then t.to_manager
            else t.from_manager end,
       it.player_id, 'zugang', 'trade', t.executed_at
  from public.fantasy_trade_items it
  join public.fantasy_trades t on t.id = it.trade_id
 where t.status = 'accepted' and t.executed_at is not null;
