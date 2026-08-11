# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Tippspiel & Fantasy App

Flutter-App (iOS/Android/Web): Tippspiel à la Kicktipp + später Fantasy à la
Sleeper. Start Bundesliga, ausbaubar auf Top-5-Ligen, NFL, NBA. UI-Sprache
und Code-Kommentare: Deutsch. Live-Demo: https://sleeperdach.github.io/MatchUp/

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
  Abhängigkeiten; **dieselbe Wertung existiert ein zweites Mal als SQL-View
  `tip_round_standings` in der Migration — bei jeder Änderung beide anpassen.**
  Das gilt auch für den Quoten-Bonus `oddsBonus` (siehe Wettquoten unten).
  Hinweis: Die View zählt nur `finished`-Spiele; der Client (`round_table.dart`)
  wertet laufende Spiele zusätzlich live mit — dieselbe Formel, anderer Zeitpunkt.
- **Spielmodi sind Feature-Module** unter `lib/features/` (tippspiel, später
  fantasy) und teilen sich den Core.
- **Navigation:** App-Shell `MainShell` mit unterer Leiste **Home / Live /
  Profil**. Eine Tipprunde öffnet `LeagueScreen` mit Tabs **Tippen / Tabelle
  / Liga** (`LeagueHubScreen` = ligainterner Chat + Regeln-Sheet); der
  Start-Tab ist die **Tabelle**. Beim Einstieg in eine Liga `activateRound()`
  benutzen (setzt Runde + Wettbewerb zusammen). Tippen gibt es nur in einer
  Liga (mit Konto) — den früheren lokalen Schnelltipp-Modus gibt es nicht mehr.
- **Deadlines serverseitig.** Tipp-Abgabe nur vor Anstoß wird per RLS in
  Supabase erzwungen (Fixtures werden dafür serverseitig gespiegelt);
  die Client-Sperre ist nur UX.

## Stack & Konventionen

- State: Riverpod (klassische Provider, kein Codegen). Models: manuelles
  `fromJson`/`toJson`, kein freezed/build_runner.
- Backend: Supabase, Projekt-Ref `zleuiewcydrazogkfafp` (eu-central-1).
  Schema in `supabase/migrations/`, Deploy per `supabase db push`.
  Geheime Zugangsdaten (DB-Passwort, Sync-Secret, Odds-Key) in
  `supabase/.env.local` (gitignored).
  **URL und Publishable-Key stehen fest in `AppConfig`**, nicht nur in
  `run_dev.sh`. Grund: der erste TestFlight-Build entstand ohne
  `--dart-define` und fiel damit stumm in den lokalen Modus — für die Tester
  war die App funktionslos („Ligen brauchen eine Server-Verbindung"). Ein
  Release-Build darf seine Server-Adresse nicht davon abhängig machen, dass
  jemand die richtigen Flags tippt. Der `sb_publishable_…`-Key ist dafür
  gedacht, im Client zu liegen (RLS schützt, nicht Geheimhaltung); der
  Service-Role-Key gehört niemals in die App. Überschreiben (z. B. Staging)
  geht weiter per `--dart-define=SUPABASE_URL=…` `…_ANON_KEY=…`.
- **`isSupabaseConfigured` heißt „Server jetzt benutzbar"**, nicht „Keys da":
  es prüft zusätzlich `AppConfig.supabaseInitialized`, das nur `main()` nach
  erfolgreichem `Supabase.initialize` setzt. Ohne diese Trennung greift jeder
  Provider auf `Supabase.instance` zu, bevor es die Instanz gibt — im Test wie
  bei fehlgeschlagener Initialisierung eine Assertion. `main()` fängt den
  Fehlschlag ab und startet im lokalen Modus, statt vor dem ersten Frame
  abzustürzen.
  **Daraus folgt für jeden Repository-Provider:** `ref.read(…RepositoryProvider)`
  erst *nach* der Prüfung aufrufen, nie davor. Der Favoriten-Tab hatte genau
  diesen Fehler — das Gate stand im Konstruktor-Argument (`enabled: user !=
  null`), das `ref.read` davor lief immer und riss den Tab mit einer Assertion
  hoch. Im Release-Build sieht das als graue Fläche aus, ohne jede Meldung.
  Wer so einen Fehler sucht: mit `--dart-define=SUPABASE_URL= --dart-define=
  SUPABASE_ANON_KEY=` starten, dann zeigt der Debug-Build den roten Schirm mit
  der echten Ursache.
- Fixture-Sync: Edge Function `supabase/functions/sync-fixtures/`
  (Deploy mit `--no-verify-jwt`, geschützt über Header `x-sync-secret`),
  Zeitplan via pg_cron (Job `sync-fixtures`, alle 10 Min, ruft die
  Function per pg_net auf). Mapping muss mit dem
  `OpenLigaDbProvider` der App konsistent bleiben. Zusätzlich darf ein
  **eingeloggter Nutzer** den Sync on-demand auslösen (JWT-Verifikation in
  der Function): `SupabaseTipStore.save` stößt ihn an, wenn ein Tipp scheitert,
  weil das Spiel in der App schon sichtbar, aber noch nicht gespiegelt ist.
- Stats-Sync: Edge Function `supabase/functions/sync-stats/` (gleiche
  Schutz-/Deploy-Konvention) füllt `player_match_stats` mit dem **vollen
  Roh-Stat-Satz aus Sportmonks** (Migration 0074: ~25 Zähler plus Rating).
  Zwei Eigenschaften sind wichtig:
  * Die Fixture-IDs kommen aus `public.fixtures` (von `sync-fixtures`
    gespiegelt), **nicht** von Sportmonks — das kostet keinen API-Request.
  * `/fixtures/multi/{ids}` liefert bis zu 25 Spiele samt Lineups und
    Ereignissen für **einen** Request (gemessen: `remaining` sinkt um 1).
    Ein voller Bundesliga-Spieltag ist damit 1 Request; Live-Scoring im
    30-Sekunden-Takt kostet ~120 Requests/h von 2.000.
  Zuordnung über `sportmonks:<player_id>` = `players.id` — kein Raten über
  Nachnamen mehr. Karten kommen aus den **Ereignissen** (nur die trennen
  glatt Rot von Gelb-Rot), alles andere aus `lineups.details`; wer das mischt,
  zählt doppelt. `STAT_CODE_MAP` in der Function muss zu
  `scoring/src/mapping.ts` passen.
  **Sportmonks kennt keinen „gehaltener Elfmeter"-Typ.** Nach
  Produktentscheidung bekommt der gegnerische Torwart die Punkte bei jedem
  `missed_penalty` — bewusst großzügig und in Teilen sachlich falsch.
  `RoundScoringService.computeStats` ist nur noch **Notfallpfad** (OpenLigaDB,
  Tore/Zu-Null); solche Zeilen tragen `source='openligadb'` bzw.
  `fullStats: false` und sind nicht mit dem vollen Satz vergleichbar.
  Roh-Stats, keine Punkte.
- **Fantasy-Punktevergabe steht an zwei Stellen** und muss gleich bleiben
  (wie `tip_scoring.dart` ↔ SQL-View): `scoring/config/scoring.config.json`
  (TypeScript-Modul, Referenz für Balance-Simulationen) und
  `lib/features/fantasy/logic/fantasy_scoring_rules.dart` (dieselbe Wertung
  für die App). Gerechnet wird in `fantasy_scoring_engine.dart`
  (`scorePlayerDetailed` liefert Summe + Aufschlüsselung).
  **Punkte sind `double`**, nicht `int` — die Wertung kennt 1,5 je Key Pass
  und −0,4 je Foul. Für die Anzeige `formatPoints()` benutzen.
  Ligen, die vor der Umstellung angelegt wurden, tragen in
  `fantasy_leagues.scoring` noch das alte 6-Kategorien-Objekt ohne `version`;
  `FantasyScoringRules.fromJson` gibt für die bewusst die Standardwertung
  zurück, statt alte Zahlen in die neue Wertung zu übernehmen.
- Wettquoten (`lib/core/data/odds/`, Quelle the-odds-api.com, Gratis-Tier):
  Der **Key bleibt serverseitig** — die Edge Function `odds` (Proxy + Cache
  `odds_cache`) liefert sie; im Client holt `SupabaseOddsProvider` nur die
  Function, `TheOddsApiProvider` ist Direkt-Fallback für den lokalen Modus.
  Matching engl. Quoten-Namen → OpenLigaDB-`shortName` (WM: FIFA-Codes) in
  `odds_team_resolver.dart` + `odds_matching.dart`. **Stufe A** (Anzeige):
  1X2-Quoten unter den Spielen. **Stufe B** (Bonus): `oddsBonus` gibt nur bei
  richtiger Tendenz +5 (Quote des Ausgangs > 5.0) bzw. +1 (≥ 2.0 über dem
  Favoriten), nicht stapelnd. Maßgeblich ist die **zum Anstoß eingefrorene**
  Quote: Tabelle `fixture_odds`, befüllt im `sync-fixtures`-Job (Matching dort
  als TS-Port — muss zum Dart-Resolver konsistent bleiben). Lokaler Modus hat
  keinen Snapshot → kein Bonus.
- **Passwort-Reset per Deep-Link.** Auf dem Handy zeigt der Link in der Mail
  auf `app.matchup.mobile://login-callback/` (`AppConfig.appDeepLink`), im Web
  weiter auf die Demo-Seite. Das Schema ist an **drei** Stellen registriert und
  muss überall gleich lauten: `AppConfig`, `ios/Runner/Info.plist`
  (`CFBundleURLTypes`) und `android/…/AndroidManifest.xml` (Intent-Filter).
  Beide Ziele müssen in Supabase unter *Authentication → URL Configuration →
  Redirect URLs* stehen, sonst ersetzt Supabase sie stillschweigend durch die
  Site-URL.
  Der `AuthFlowType.implicit` ist dafür Voraussetzung: `supabase_flutter`
  erkennt einen Auth-Deeplink nur an `access_token` **im Fragment**, und genau
  das liefert der Implicit-Flow (bei PKCE wäre es `?code=`, siehe
  `_isAuthCallbackDeeplink` im Paket).
  **Der Listener in `main()` allein genügt nicht:** `Supabase.initialize`
  verarbeitet den Start-Link intern, bevor `main()` weiterläuft — beim
  Kaltstart aus der Mail wäre das `passwordRecovery`-Event schon verpufft.
  Deshalb liest `_pruefeRecoveryStartlink()` den Start-Link zusätzlich selbst
  und prüft auf `type=recovery`. Wer den Listener anfasst, muss diesen zweiten
  Pfad mitdenken, sonst landet der Tester auf der Startseite statt beim
  Passwort-Screen.
- Liga-Chat: Tabelle `tip_round_messages` (RLS: nur Mitglieder), Live über
  Supabase Realtime (`messageStream`). Ungelesen-Hinweis am Liga-Symbol wird
  lokal pro Gerät getrackt (`chatLastReadProvider`, SharedPreferences).
- Fixture-IDs sind Provider-qualifiziert (`openligadb:77554`) — identisch in
  App und Datenbank.
- Saison = Startjahr (2025 ⇒ 2025/26).
- Spielerpool in `public.players`: kuratierter Seed (Migration 0004) plus
  aktuelle Kader aus TheSportsDB (Gratis-Key, je Verein max. 10 Spieler;
  Migration 0010, generiert per `tools/import_player_pool.py`). `club` ist
  immer der kanonische OpenLigaDB-Name, sonst bricht das Stats-Matching.
  ids: `seed:*` bzw. `tsdb:*`. Echter Voll-Kader nur mit Bezahl-Feed.

## Befehle

```sh
flutter test                               # alle Unit-Tests (Scoring, Parser, Odds)
flutter test test/odds_bonus_test.dart     # eine Datei
flutter test --plain-name "Stufen stapeln" # einzelner Test per Name
flutter analyze
flutter run                                # mit Server — Keys stecken in AppConfig
flutter build ipa                          # TestFlight; braucht keine Flags mehr
```

Server-Deploy (Zugangsdaten aus `supabase/.env.local`, CLI ist eingeloggt +
verlinkt):

```sh
supabase db push                                          # Migrationen
supabase functions deploy sync-fixtures --no-verify-jwt   # bzw. odds / sync-stats
```

Web-Demo (`gh-pages`): bewusst **ohne** Service Worker bauen, sonst cacht der
alte Build aggressiv:

```sh
flutter build web --release --pwa-strategy=none --base-href "/MatchUp/" \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
# danach flutter_service_worker.js löschen, .nojekyll setzen,
# Inhalt von build/web auf Branch gh-pages pushen
```

## Live-Update (immer nach Änderungen)

Simulator **und** Web-Demo nach jeder Änderung auf den neuesten Stand bringen,
nicht erst auf Nachfrage:

- **Simulator (auf dem MacBook):** soll **durchgehend mitlaufen**. Dafür
  abgekoppelt starten und über eine PID-Datei steuern — sonst reißt das Ende
  eines Shell-Kommandos die App mit („Lost connection to device"):
  ```sh
  nohup flutter run -d <udid> --pid-file=/tmp/flutter.pid \
    > /tmp/live.log 2>&1 < /dev/null & disown
  kill -USR1 "$(cat /tmp/flutter.pid)"   # Hot-Reload
  kill -USR2 "$(cat /tmp/flutter.pid)"   # Hot-Restart (Provider/Struktur)
  xcrun simctl launch <udid> app.matchup.mobile   # App nach vorn holen
  ```
  `setsid` gibt es auf macOS **nicht**; `nohup … & disown` genügt. `flutter
  run` nie an ein Kommando hängen, das ein Timeout haben kann.
  **„Restarted application in 2 ms" ist kein Fehlersignal** — ob der Restart
  wirkte, sieht man daran, dass die App wieder auf dem Home-Tab steht.
  Den Stand per `xcrun simctl io <udid> screenshot`
  prüfen. Tippen geht doch — über die Fensterkoordinaten des Simulators:
  ```sh
  osascript -e 'tell application "System Events" to tell process "Simulator" \
    to click at {X, Y}'   # Fensterposition/-größe vorher per AppleScript holen
  ```
  Deep-Links (Passwort-Reset) lassen sich so komplett durchspielen:
  `xcrun simctl terminate <udid> app.matchup.mobile`, dann
  `xcrun simctl openurl <udid> "app.matchup.mobile://login-callback/#access_token=X&type=recovery"`
  — iOS fragt „In MatchUp öffnen?", der Klick bestätigt.
  **Synthetische Taps sind unzuverlässig:** Die Navi-Kapsel schwebt
  (`extendBody`), daneben liegt der Inhalt — Fehlklicks öffnen News-Links im
  In-App-Browser. Für Layout-Prüfungen sind **Golden-Vorschauen** unter
  `test/goldens/` das verlässlichere Mittel (`flutter test --update-goldens
  test/<name>_preview_test.dart`, dann die PNG ansehen). Genau so ist
  aufgefallen, dass Heim/Auswärts auf dem Spielfeld vertauscht waren.
- **Web-Demo:** mit dem Build-/Deploy-Ablauf oben neu nach `gh-pages` pushen
  und live verifizieren (md5 von `main.dart.js` gegen den Build vergleichen;
  GitHub Pages propagiert ~15–60 s).
