# Tippspiel & Fantasy App

Flutter-App (iOS/Android/Web): Tippspiel à la Kicktipp + später Fantasy à la
Sleeper. Start Bundesliga, ausbaubar auf Top-5-Ligen, NFL, NBA. UI-Sprache
und Code-Kommentare: Deutsch.

## Architektur-Leitlinien

- **Sport-agnostischer Kern.** Keine Liga-/Sport-Spezifika außerhalb von
  `lib/core/models/models.dart` (`Leagues`-Registry) und den Daten-Adaptern.
  Modell: Sport → League → Season → Round (Spieltag/Week) → Fixture.
- **Datenquellen hinter `SportsDataProvider`** (`lib/core/data/`). Pro Liga
  ein Adapter; aktuell `OpenLigaDbProvider` (Bundesliga, kostenlos). Neue
  Liga = neuer `LeagueInfo`-Eintrag + ggf. neuer Adapter, kein Umbau.
- **Scoring ist konfigurierbar, nie hartkodiert.** `ScoringRules` als Daten
  (JSON-fähig, liegt pro Tipprunde in Supabase als JSONB). Die Engine
  `lib/features/tippspiel/logic/tip_scoring.dart` ist pure Dart ohne
  Abhängigkeiten; dieselbe Logik existiert als SQL-View
  `tip_round_standings` in der Migration — bei Änderungen beide anpassen.
- **Spielmodi sind Feature-Module** unter `lib/features/` (tippspiel, später
  fantasy) und teilen sich den Core.
- **Navigation:** `HomeScreen` (Ligen wählen/erstellen/beitreten) →
  `LeagueScreen` (Tabs: Tippen / Rangliste / Meine Punkte). Tippen gibt es
  nur innerhalb einer Liga bzw. im lokalen Schnelltipp-Modus; beim Einstieg
  in eine Liga `activateRound()` benutzen (setzt Runde + Wettbewerb).
- **Deadlines serverseitig.** Tipp-Abgabe nur vor Anstoß wird per RLS in
  Supabase erzwungen (Fixtures werden dafür serverseitig gespiegelt);
  die Client-Sperre ist nur UX.

## Stack & Konventionen

- State: Riverpod (klassische Provider, kein Codegen). Models: manuelles
  `fromJson`/`toJson`, kein freezed/build_runner.
- Backend: Supabase, Projekt-Ref `zleuiewcydrazogkfafp` (eu-central-1).
  Schema in `supabase/migrations/`, Deploy per `supabase db push`.
  Zugangsdaten (DB-Passwort, Sync-Secret, Keys) in `supabase/.env.local`
  (gitignored). Client läuft ohne Konfiguration im lokalen Modus; Keys per
  `--dart-define=SUPABASE_URL=…` `--dart-define=SUPABASE_ANON_KEY=…`.
- Fixture-Sync: Edge Function `supabase/functions/sync-fixtures/`
  (Deploy mit `--no-verify-jwt`, geschützt über Header `x-sync-secret`),
  Zeitplan via pg_cron (Job `sync-fixtures`, alle 10 Min, ruft die
  Function per pg_net auf). Mapping muss mit dem
  `OpenLigaDbProvider` der App konsistent bleiben.
- Stats-Sync: Edge Function `supabase/functions/sync-stats/` (gleiche
  Schutz-/Deploy-Konvention) füllt `player_match_stats` (Tore/Zu-Null aus
  OpenLigaDB). Die Matching-Logik ist 1:1 zu
  `RoundScoringService.computeStats` — bei Änderungen beide anpassen. Der
  Client liest die Tabelle über `FantasyStatsSource` und fällt für nicht
  gespiegelte Spieltage auf die Live-Berechnung zurück. Roh-Stats, keine
  Punkte (die hängen an `FantasyScoring`).
- Fixture-IDs sind Provider-qualifiziert (`openligadb:77554`) — identisch in
  App und Datenbank.
- Saison = Startjahr (2025 ⇒ 2025/26).

## Befehle

```sh
flutter test       # Unit-Tests (Scoring, Parser)
flutter analyze
flutter run
```
