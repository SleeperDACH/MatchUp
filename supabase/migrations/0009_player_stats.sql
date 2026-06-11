-- Stats-Feed (Phase 6): serverseitige Spieler-Leistungsdaten je Spieltag.
--
-- Bisher berechnete der Client die Roh-Stats (Tore + Zu-Null) live aus dem
-- kostenlosen OpenLigaDB-Feed (RoundScoringService). Das skaliert nicht für
-- einen vollständigen Stats-Feed und ist an OpenLigaDBs Grenzen gebunden
-- (keine Assists/Karten/Minuten/Aufstellungen).
--
-- Diese Tabelle ist die anbieter-neutrale Quelle der Wahrheit: serverseitig
-- befüllt (Edge Function sync-stats füllt aktuell Tore/Zu-Null aus
-- OpenLigaDB), Schema und Scoring sind bereits auf Assists, Karten und
-- Minuten vorbereitet. Sobald ein reicherer Feed angebunden wird, füllt er
-- dieselben Spalten — ohne Client-Umbau.
--
-- Roh-Stats, KEINE Punkte: die Fantasy-Punkte hängen von der
-- ligaspezifischen FantasyScoring-Konfiguration ab und werden im Client
-- (scorePlayer) bzw. später serverseitig daraus berechnet.

create table public.player_match_stats (
  season      int  not null,
  round       int  not null,
  player_id   text not null references public.players (id),
  goals       int  not null default 0,
  assists     int  not null default 0,
  minutes     int  not null default 0,
  yellow      int  not null default 0,
  red         int  not null default 0,
  clean_sheet boolean not null default false,
  appeared    boolean not null default false,
  updated_at  timestamptz not null default now(),
  primary key (season, round, player_id)
);

create index player_match_stats_round_idx
  on public.player_match_stats (season, round);

alter table public.player_match_stats enable row level security;

create policy "Spieler-Stats sind öffentlich lesbar"
  on public.player_match_stats for select using (true);
-- Schreiben nur über service_role (Edge Function sync-stats), keine Policy.
