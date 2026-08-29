-- Balleroberungen sind ein eigenes Feld — und hießen bisher falsch.
--
-- Aufgefallen an einer Rückfrage: „Pejcinovic hat in 90 Minuten doch nicht nur
-- eine Balleroberung gehabt." Die angezeigte Zahl stimmte (er spielte 63
-- Minuten und hatte 26 Ballkontakte), aber **die Beschriftung war falsch**:
-- Die App nannte `interceptions` „Balleroberung". Sportmonks führt beides
-- getrennt, und die Felder sind nicht dasselbe:
--
--   84 Spieler ab 60 Minuten, vier Partien
--   interceptions   Summe  67   Schnitt 0,8   max  4
--   ball-recovery   Summe 245   Schnitt 2,9   max 14
--   verschieden bei 56 von 84 Spielern
--
-- Bei Pejcinovic waren beide zufällig 1 — deshalb sah die Zahl richtig aus und
-- die Beschriftung trotzdem falsch.
--
-- `interceptions` heißt jetzt **„Abgefangener Ball"**, und `ball-recovery`
-- kommt als **„Balleroberung"** dazu.
--
-- **Nicht in die Defensiv-Meilensteine.** Deren Schwellen sind ohne dieses
-- Feld geeicht; gemessen verschöbe es die Summe je Spieler so:
--
--          ohne  ->  mit        Schwelle
--   TW     0     ->  8          9
--   ABW    5     ->  8          9
--   MF     1     ->  6          10
--   ST     1     ->  2          8
--
-- Beim Torwart spränge der Median von 0 auf 8, also direkt an die erste
-- Schwelle — ein bestehender Bonus würde stillschweigend zum Selbstläufer.
-- Balleroberungen zählen deshalb einzeln (0,4 wie eine Klärung: häufig,
-- einzeln wenig wert), nicht in den Meilenstein.

alter table player_match_stats
  add column if not exists ball_recovery int not null default 0;

comment on column player_match_stats.ball_recovery is
  'Balleroberungen (Sportmonks-Code ball-recovery). Nicht zu verwechseln mit '
  'interceptions — das sind abgefangene Bälle und rund viermal seltener.';
