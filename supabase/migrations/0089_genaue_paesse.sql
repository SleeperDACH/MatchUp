-- Genaue Pässe werden bepunktet.
--
-- Der Code für das Feld heißt bei Sportmonks **`accurate-passes`** — nicht
-- `successful-passes`, obwohl es den Typ im Katalog gibt (ID 81). Gemessen an
-- vier echten Spieltag-1-Partien: `accurate-passes` liegt für **jeden** der 32
-- Spieler vor, `successful-passes` in keinem einzigen Datensatz. Wer hier den
-- Namen rät, holt sich eine Spalte, die immer 0 bleibt.
--
-- Die Wertung läuft über **positionsabhängige Schwellen**, nicht über einen
-- Wert je Pass: Ein Mittelfeldspieler kommt auf Dutzende, ein Stürmer auf eine
-- Handvoll. Ein Punktwert je Pass müsste so klein sein, dass er in der Anzeige
-- verschwindet — und er belohnte die Position, nicht die Leistung.
--
-- Gemessen (nur Spieler ab 60 Minuten, vier Partien):
--
--   TW   Median 25   oberes Viertel 29   max  30
--   ABW  Median 34   oberes Viertel 53   max 110
--   MF   Median 28   oberes Viertel 37   max  65
--   ST   Median 14   oberes Viertel 15   max  30
--
-- Die Schwellen in `fantasy_scoring_rules.dart` liegen deshalb je Position
-- anders — 30 genaue Pässe sind für einen Stürmer herausragend und für einen
-- Verteidiger unterdurchschnittlich.

alter table player_match_stats
  add column if not exists accurate_passes int not null default 0;

comment on column player_match_stats.accurate_passes is
  'Genaue Pässe (Sportmonks-Code accurate-passes). Basis der Pass-Boni; die '
  'Schwellen stehen positionsabhängig in der Wertung, nicht hier.';
