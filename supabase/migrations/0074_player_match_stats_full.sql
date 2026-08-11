-- Voller Roh-Stats-Satz je Spieler und Spiel (Sportmonks).
--
-- Migration 0009 legte die Tabelle anbieter-neutral an und hielt schon damals
-- fest: „Schema und Scoring sind bereits auf Assists, Karten und Minuten
-- vorbereitet. Sobald ein reicherer Feed angebunden wird, füllt er dieselben
-- Spalten — ohne Client-Umbau." Genau das passiert jetzt: sync-stats zieht die
-- Daten aus Sportmonks-Lineups statt aus OpenLigaDB.
--
-- Bis hierher konnte der Feed nur Tore und Zu-Null füllen; assists/minutes/
-- yellow/red standen fest auf 0 und `appeared` war schlicht `goals > 0` — wer
-- nicht traf, galt als nicht eingesetzt. Die Punktevergabe
-- (scoring/config/scoring.config.json) bewertet aber ~25 Kategorien. Die
-- Spalten unten sind exakt die Felder von `PlayerEvents` (scoring/src/types.ts)
-- — eine Spalte je Zählwert, damit die Wertung auch serverseitig auswertbar
-- bleibt und nicht in einem JSONB-Klumpen verschwindet.
--
-- Weiterhin gilt: Roh-Stats, KEINE Punkte. Die Punkte hängen an der
-- ligaspezifischen Scoring-Konfiguration und entstehen erst beim Auswerten.

alter table public.player_match_stats
  -- Offensive
  add column if not exists penalty_goals        int  not null default 0,
  add column if not exists big_chances_created  int  not null default 0,
  add column if not exists key_passes           int  not null default 0,
  add column if not exists shots_on_target      int  not null default 0,
  add column if not exists successful_dribbles  int  not null default 0,
  -- Defensive / Torwart
  add column if not exists goals_conceded       int  not null default 0,
  add column if not exists saves                int  not null default 0,
  add column if not exists penalties_saved      int  not null default 0,
  add column if not exists tackles_won          int  not null default 0,
  add column if not exists interceptions        int  not null default 0,
  add column if not exists clearances           int  not null default 0,
  add column if not exists blocked_shots        int  not null default 0,
  -- Negativ
  add column if not exists second_yellow        int  not null default 0,
  add column if not exists own_goals            int  not null default 0,
  add column if not exists penalties_missed     int  not null default 0,
  add column if not exists errors_lead_to_goal  int  not null default 0,
  add column if not exists big_chances_missed   int  not null default 0,
  add column if not exists offsides             int  not null default 0,
  add column if not exists fouls                int  not null default 0,
  add column if not exists possession_lost      int  not null default 0,
  -- Sportmonks-Rating 0–10; NULL = keine Wertung vergeben (nicht 0!), deshalb
  -- als einzige Spalte nullable.
  add column if not exists rating               numeric(3,1);

-- Herkunft der Zeile, damit ein OpenLigaDB-Notfalleintrag (nur Tore/Zu-Null)
-- nicht mit einem vollständigen Sportmonks-Satz verwechselt wird. Ohne das
-- sähe eine Notfallzeile wie ein Spieler aus, der 90 Minuten lang nichts
-- getan hat — inklusive aller Null-Werte in der Punkte-Aufschlüsselung.
alter table public.player_match_stats
  add column if not exists source text not null default 'sportmonks'
    check (source in ('sportmonks', 'openligadb'));

comment on column public.player_match_stats.source is
  'sportmonks = vollständiger Stat-Satz; openligadb = Notfall, nur goals/clean_sheet belastbar.';

-- Die Altbestände stammen sämtlich aus dem OpenLigaDB-Sync und haben nur
-- Tore/Zu-Null. Als solche kennzeichnen, damit die Anzeige sie nicht als
-- vollständige Sportmonks-Sätze ausgibt.
update public.player_match_stats set source = 'openligadb';
