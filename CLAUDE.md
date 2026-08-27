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
- **Die Karten sagen nicht mehr, was zu tun ist.** Sie trugen dafür einen
  Sockel; der ist auf ausdrücklichen Wunsch bei beiden Sorten entfernt (siehe
  unten). Der Grundsatz dahinter — was zu tun ist, gehört auf die Karte und
  nicht in einen Kasten obendrüber — bleibt gültig für den Tag, an dem so
  etwas zurückkommt: Eine „Jetzt"-Karte am Kopf gab es; sie nahm zu viel Platz für
  eine Sache, die ohnehin auf die Karte gehört. (Am Kopf steht seit
  „Richtung A" wieder eine Karte, aber eine **andere**: das nächste Spiel des
  eigenen Vereins, siehe unten. Sie sammelt keine Aufgaben ein, sie zeigt
  einen Inhalt.) Jede Karte trägt ihren eigenen Zustand:
  `offeneTippsProvider(roundId)`
  (`lib/app/home_tip_status.dart`) zählt die ungetippten Spiele **derselben**
  Do–Mi-Woche, die auch der Tippen-Tab öffnet (`buildWeeks`/
  `currentWeekIndex`) — sonst stünden auf Karte und Feed verschiedene Zahlen.
  Fristen stehen absolut („bis Fr., 20:30", `kurzeFrist`), nicht als
  Countdown: auf einer Karte, die minutenlang steht, veraltet eine Restdauer.
  **Ligainterne Tipprunden hängen an der Ligakarte**: sie tauchen im
  Tippspiel-Abschnitt bewusst nicht auf (erreichbar über die Liga), ihre
  offenen Tipps hätten sonst nirgends Platz. Läuft ein Draft, gewinnt der —
  seine Uhr tickt in Minuten.
- **Fantasy und Tippspiel sind zwei Kartenreihen, News eine schmale
  Querleiste.** Die Tipprunden waren zwischendurch Zeilen — andere Form für
  den zweiten Bereich, und der Name bekam die volle Breite statt der knapp
  hundert Punkte einer Karte. Zurückgedreht auf ausdrücklichen Wunsch. Wer das
  wieder anfasst, sollte den Grund kennen, der einmal dagegen sprach: Zwei
  gleich gebaute Reihen untereinander lassen den halben Schirm gleich
  aussehen. Was sie jetzt trennt, ist **Höhe, Marke und Farbe** statt der
  Form — die Tipprunden-Karte ist flacher (`_kTipCardHeight` 126 gegen 132),
  trägt das Gold des Tippspiels und ein anderes Zeichen. Und der Preis bleibt:
  Der Rundenname muss auf zwei Zeilen einer 95 Punkte breiten Karte passen.
  Die Karten tragen ihre Farbe als **Hauch aus der Ecke** (`_kartenFlaeche`),
  nicht als Fläche: oben links, wo die Marke ohnehin in derselben Farbe steht,
  bei drei Vierteln der Diagonale verklungen. Beide Extreme davor waren falsch
  — der kräftige Verlauf, weil vier Farbflächen gleich laut riefen und
  ausgerechnet den Modus ansagten, und das flache Grau danach, weil der Reihe
  damit jede Identität fehlte (siehe „Einfarbig ist auch kein Zustand"). Die
  Modusfarbe (`ui/league_colors.dart`: Redraft grün, Dynasty rot) steckt in der
  30er-Marke oben links; ein eigenes Liga-Logo sticht sie weiterhin.
  **Keine der beiden Karten hat noch einen Sockel** — beide zeigen Marke, Name
  und Untertitel, sonst nichts, und teilen sich deshalb ein Maß
  (`_kKartenHoehe`, 108 statt vorher 146 und 140). Was sie unterscheidet, sind
  Zeichen und Farbe.

  **Was damit vom Startbildschirm verschwunden ist**, sollte kennen, wer es
  zurückholen will: „Draft läuft" samt Pick-Uhr, „Kader steht", der eigene
  Tabellenplatz, „Alles getippt" und „18 Tipps offen · bis Fr., 18:30". Auf
  ausdrücklichen Wunsch entfernt — die Zeile stand bei den meisten Ligen die
  meiste Zeit auf „Offen" und trug dafür Höhe. Damit sind auch der Ton-Typ
  `_Sockel`, `_StatusZeile` und der gefärbte Rahmen bei „dringend" weg.

  **Nebeneffekt, der zählt:** Je Ligakarte fallen drei Provider weg
  (`myFantasyRankProvider`, `fantasyTipRoundProvider`, `offeneTippsProvider`),
  je Tippkarte einer — zwei davon gingen pro Karte ans Netz. Bei vier Ligen
  und zwei Runden sind das zehn Abrufe weniger beim Öffnen des
  Startbildschirms. `lib/app/home_tip_status.dart` ist dadurch **ohne
  Aufrufer**; die Datei bleibt bewusst stehen und sagt das im Kopf, weil die
  Zählregel darin (dieselbe Do–Mi-Woche wie der Tippen-Tab) nichts ist, was
  man versehentlich ein zweites Mal erfindet.
  Die Kartenbreite rechnet `leagueCardWidth` aus der Bildschirmbreite, geteilt
  durch **3,75**: die vierte Karte wird am rechten Rand angeschnitten. Vorher
  passten genau vier hinein — das war als Ordnung gedacht und las sich als
  starres Raster, und wer eine fünfte Liga hatte, fand sie nicht.
  Zustandstexte darin schrumpfen (`FittedBox`) statt zu kappen — „Kader
  ste…" sagt nichts. Und jede Karte zeigt **Zustand**
  (`fantasyStatus`, `logic/league_status.dart`): vor dem ersten gewerteten
  Spieltag rendert `FantasyRankChip` absichtlich nichts, ohne Zustandszeile
  wäre die Karte dann leer und von jeder anderen ununterscheidbar.
- **Keine Material-Auswahlelemente.** `SegmentedButton`, `ChoiceChip` und
  `FilterChip` ziehen ihre Auswahlfarbe aus `secondaryContainer` — aus dem
  grünen Seed wird das ein stumpfes Oliv, und der Rahmen passt nirgends zum
  übrigen Look. Stattdessen: `PillChip`/`PillSelector` (`app/widgets/`) für
  Umschalter und Filter, `OptionTile` (`core/ui/`) für Entscheidungen, die
  eine Begründung brauchen (Liga-Modus, Sichtbarkeit), `CompetitionPicker`
  für Wettbewerbe (mit Wappen — als Text unterscheiden sich „Bundesliga" und
  „2. Bundesliga" kaum).
- **Formulare und Einstellungslisten benutzen `FormSection`**
  (`core/ui/form_section.dart`): kleine Versal-Überschrift, optional ein
  erklärender Satz, Inhalt in abgesetzter Fläche — dazu `FormError` und
  `FormActionBar`. Die Erstellen-Formulare und die Tipprunden-Einstellungen
  sahen vorher verschieden aus, obwohl sie dieselbe Sache betreffen. Der
  Hauptknopf gehört in die `FormActionBar` am unteren Rand, **nicht** ans
  Ende der Liste: beim Tippspiel liegt dazwischen der ganze Wertungs-Editor.
  Steuerelemente darin bringen **keine eigene Fläche** mit (`filled: false`
  bei Textfeldern), sonst steht ein Kasten im Kasten.
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
- **Kader-Sync: Edge Function `supabase/functions/sync-squads/`** (gleiche
  Schutz-/Deploy-Konvention) holt die kompletten Kader der 18 Bundesliga-
  Vereine von Sportmonks, spielt Zugänge per Upsert ein und entfernt Abgänge
  über `fantasy_prune_departed_players` (Migration 0073). Zwei Sicherungen:
  Geprunt wird **nur**, wenn alle 18 Kader plausibel geladen wurden
  (`MIN_SQUAD` 15) — sonst reißt eine API-Lücke halbe Kader weg; und gelöscht
  wird nur, wer in **keiner** referenzierenden Tabelle steht (nicht gedraftet,
  nicht gerostert, keine Trades/Waiver, keine Match-Stats). Ein gedrafteter
  Spieler verschwindet niemandem aus dem Kader.
  **Der Zeitplan ist der eigentliche Punkt** (Migration 0076, täglich 04:17
  UTC): Die Function war geschrieben, committet und hier dokumentiert — aber
  monatelang **weder deployed noch eingeplant**. Der Pool stand deshalb auf
  dem Stand eines einmaligen Hand-Imports; Zugänge fehlten, Abgänge standen
  weiter drin. Wer eine Function schreibt, ist erst fertig, wenn sie läuft:
  `supabase functions list` zeigt, was wirklich draußen ist, und
  `select * from cron.job` , was wirklich getaktet ist.
  Der `x-sync-secret` steht dabei **nicht** in der Migration — das Repo ist
  öffentlich. Er kommt aus dem Vault (`select vault.create_secret('<SECRET>',
  'sync_secret')`).
  **`net.http_post` bricht nach 5 Sekunden ab** (pg_net-Standard), ein voller
  Kader-Lauf über 18 Vereine dauert rund 8 — deshalb steht in Migration 0077
  `timeout_milliseconds := 120000`. Ohne das ist der Fehler besonders
  hinterhältig: In `cron.job_run_details` stünde „succeeded" (pg_net setzt den
  Auftrag ja erfolgreich ab), und ob die Function ihren Lauf zu Ende bringt,
  wenn der Aufrufer die Verbindung kappt, ist nicht garantiert. Wer hier eine
  Edge Function einplant, die länger als fünf Sekunden läuft, prüft das
  Ergebnis in `net._http_response` (`status_code`, `timed_out`) — nicht in
  `cron.job_run_details`.
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
  **Sportmonks hat zwei Typ-Nummernkreise, und sie überschneiden sich:** im
  `event`-Kreis ist 15 ein Eigentor, im `statistic`-Kreis ist 83 eine Rote
  Karte. Die Torjägerliste zeigte deshalb monatelang Rote Karten statt Tore
  (Statistik-Typ für Tore ist **208**). Jede Typ-Zahl vor dem Einbau gegen
  `/v3/core/types/<id>` prüfen und auf `model_type` schauen.
  Die Torjäger-Abfrage braucht zwingend `filters=seasonTopscorerTypes:208` —
  `topscorerTypes` wird **stillschweigend ignoriert**, und ohne Filter mischt
  die Antwort Karten, Tore und Vorlagen nach Typ gruppiert; die Tore fangen
  erst auf Seite 2 an, `per_page=25` sieht also nur Karten.
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

## Anmeldung über Google und Apple

Zwei Wege, und welcher genommen wird, entscheidet die Plattform — nicht eine
Einstellung (`lib/features/auth/social_auth.dart`):

| | Google | Apple |
|---|---|---|
| iOS/macOS | nativ (`google_sign_in`) | nativ (`sign_in_with_apple`) |
| Android | nativ (`google_sign_in`) | Browser (`signInWithOAuth`) |
| Web | Browser | Browser |

**Nativ** heißt: Das System zeigt seinen eigenen Auswahldialog, liefert ein
ID-Token, und das geht per `signInWithIdToken` an Supabase — die Sitzung steht,
wenn der Aufruf zurückkommt. **Browser** heißt: `signInWithOAuth` öffnet ein
Fenster und kehrt *sofort* zurück; die Sitzung entsteht erst, wenn der
Deep-Link `app.matchup.mobile://login-callback` wieder in der App landet.
Deshalb hängt nach dem Knopf nichts, was die Sitzung braucht. Der Rückgabewert
`false` bedeutet ausschließlich „abgebrochen" — und Abbruch ist kein Fehler,
die Oberfläche zeigt dann nichts Rotes an.

Drei Dinge, die beim Nachbauen Zeit kosten:

- **Android braucht die *Web*-Client-ID, nicht die Android-Client-ID.** Sie
  geht als `serverClientId` in `initialize()`; das ID-Token wird auf sie
  ausgestellt, und genau diese `aud` prüft Supabase. Wer die Android-Client-ID
  einträgt, bekommt „Invalid audience". Der Android-Client selbst wird in der
  Google Cloud Console nur über Paketname + SHA-1 hinterlegt.
- **Seit `google_sign_in` 7 liefert `authentication` nur noch das ID-Token.**
  Ein Access-Token gäbe es allein über den Autorisierungs-Client — Supabase
  braucht keins. Anleitungen, die `accessToken` aus `authentication` lesen,
  beziehen sich auf Version 6.
- **Der Nonce ist bei Apple Pflicht und wird zweimal gebraucht:** Apple bekommt
  den SHA-256-Abdruck, Supabase das Original. Wer beiden denselben Wert gibt,
  bekommt „Nonce mismatch".

**Ein Konto ohne Profil ist ein toter Account.** `fantasy_league_members`,
Chats und Freundschaften zeigen per Fremdschlüssel auf `profiles`; fehlt die
Zeile, scheitert jeder Liga-Beitritt mit
`fantasy_league_members_user_id_fkey` (23503), und der Homescreen grüßt mit
„Willkommen" statt mit dem Namen. Gemessen am 27.08.2026: **drei von
fünfundzwanzig** Konten waren in diesem Zustand, alle per E-Mail angelegt.

Der Weg dorthin: `signUp` legt Konto und Profil in **zwei** Schritten an. Geht
der zweite schief — etwa weil der Nutzername vergeben ist (23505) —, bleibt
das Konto stehen. Ein zweiter Versuch mit anderem Namen scheitert dann an
„Für diese E-Mail existiert bereits ein Konto", und der Betroffene sitzt fest.
Zwei Änderungen halten das ab:

* **`currentProfileProvider` legt das Profil nach**, wenn keins da ist. Dort
  kommt jeder Weg vorbei (Kaltstart, E-Mail-Login, Google, Apple), und die
  Heilung schluckt ihren Fehler — ein Profil, das sich nicht anlegen lässt,
  darf nicht auch noch den Start blockieren. Vorher lief
  `ensureProfileFromIdentity` **nur** hinter Google/Apple; E-Mail-Konten
  hatten keinen Weg zurück.
* **Die Fehlermeldung bei der Registrierung sagt, dass das Konto existiert.**
  „Der Nutzername ist bereits vergeben" allein schickte in die Sackgasse.

**Profile entstehen hier nicht von selbst.** `signUp` legt die `profiles`-Zeile
mit dem selbst gewählten Namen an — über Google oder Apple läuft dieser Weg
nie. `AuthRepository.ensureProfileFromIdentity` holt das nach und leitet den
Namen ab (`username_vorschlag.dart`, reine Funktionen mit Tests). Ohne das wäre
der Nutzer angemeldet und stünde in jeder Liga, Tabelle und jedem Chat
namenlos da. Der Name ist ein Vorschlag, kein Pflichtfeld — ändern geht über
`updateUsername`. **Apple gibt den Namen nur bei der allerersten Anmeldung
heraus**, danach nie wieder; wer ihn da nicht mitnimmt, hat ihn für immer
verloren.

Die Knöpfe zeigt der Anmeldescreen nur, wo sie funktionieren
(`AppConfig.hasGoogleSignIn` / `hasAppleSignIn`) — ein Anmeldeweg, der in eine
Fehlermeldung läuft, ist schlechter als keiner. Im Test sind beide Flags über
`googleSignInAvailableProvider` / `appleSignInAvailableProvider`
überschreibbar; ohne das zeigte die Golden-Vorschau genau das, was der Nutzer
später *nicht* sieht.

### Einrichtung (Konsolen, einmalig)

Der Code steht; ohne diese Schritte bleiben beide Knöpfe unsichtbar.

1. **Google Cloud Console** → APIs & Dienste → Anmeldedaten:
   * OAuth-Client **Web** anlegen. Als autorisierte Weiterleitung
     `https://zleuiewcydrazogkfafp.supabase.co/auth/v1/callback` eintragen.
   * OAuth-Client **iOS** anlegen, Bundle-ID `app.matchup.mobile`.
   * OAuth-Client **Android** anlegen, Paketname `app.matchup.mobile`, dazu
     **beide** SHA-1: der des Upload-Keystores (`keytool -list -v -keystore
     ~/keys/matchup-upload.jks`) **und** der des Play-App-Signing-Keys aus der
     Play Console. Fehlt der zweite, funktioniert die Anmeldung im Testgerät
     und scheitert für jeden, der die App aus dem Store lädt.
2. **Supabase** → Authentication → Providers → Google aktivieren: Secret des
   **Web**-Clients eintragen, und unter „Client IDs" die **Web-** und die
   **iOS**-Client-ID (kommagetrennt). Die Android-Client-ID gehört **nicht**
   dorthin: Sie taucht nie als `aud` eines ID-Tokens auf — Android stellt seine
   Token auf die Web-Client-ID aus (`serverClientId`), und nur die prüft
   Supabase. Der Android-Client existiert allein, damit Google die App an
   Paketname + SHA-1 wiedererkennt.
3. **Apple Developer** → Identifiers:
   * Beim App-Identifier `app.matchup.mobile` die Capability **Sign in with
     Apple** einschalten. Sie muss im Provisioning-Profil stecken, sonst
     scheitert schon der iOS-Build an `Runner.entitlements`.
   * Eine **Service-ID** für den Browser-Weg (Android/Web) anlegen, Rückkehr
     `…supabase.co/auth/v1/callback`.
   * Einen **Key** mit Sign-in-with-Apple anlegen und in Supabase →
     Authentication → Providers → Apple hinterlegen.
4. **Werte in `AppConfig`** eintragen (`googleIosClientId`,
   `googleWebClientId`, `appleServiceId`) — als `defaultValue` fest im Code,
   aus demselben Grund wie die Supabase-Keys: ein Build ohne `--dart-define`
   hätte sonst keine Anbieter-Anmeldung, und zwar wortlos. Die Werte sind
   öffentlich; geheim ist allein das Client-*Secret*, und das liegt nur im
   Supabase-Dashboard.
5. **`ios/Runner/Info.plist`**: das *umgekehrte* Schema der iOS-Client-ID
   (`com.googleusercontent.apps.…`) als weiteren `CFBundleURLTypes`-Eintrag
   ergänzen. Ohne das kehrt die Google-Anmeldung auf iOS nicht in die App
   zurück. **Steht noch aus** — die Client-ID gibt es noch nicht, und ein
   falsches Schema ist schlimmer als keins.
6. **Redirect-URLs in Supabase** (Authentication → URL Configuration): der
   Deep-Link steht dort schon vom Passwort-Reset; für den Browser-Weg wird
   nichts Weiteres gebraucht.

`ios/Runner/Runner.entitlements` ist angelegt und in allen drei
Build-Konfigurationen als `CODE_SIGN_ENTITLEMENTS` eingehängt. Solange die
Capability am App-Identifier fehlt, **verschärft das den iOS-Build-Fehler**:
Zur fehlenden Signatur kommt dann ein fehlendes Entitlement.

### Die Teilnehmerzahl war nicht verwaist — die Seite war es

`LeagueSettingsPage` in `fantasy_settings_screen.dart` konnte die
Teilnehmerzahl schon immer bearbeiten. Sie wurde nur **in keiner Datei
geöffnet**: Im Zahnrad standen Draft-, Playoff-, Punkte- und
Sichtbarkeits-Einstellungen, aber nichts, was zur Liga-Größe führte. Wer sie
nach dem Anlegen ändern wollte, hatte keinen Weg dorthin. Jetzt steht unter
„Regeln & Format" die Kachel **Teilnehmerzahl** mit dem aktuellen Stand im
Untertitel.

Zwei Dinge, die dabei mit hochkamen:

- **Ein `update`, das keine Zeile trifft, ist kein Fehler.** Das Repository
  filterte zusätzlich auf `.eq('draft_status', 'setup')`. Wäre die Seite je
  erreichbar gewesen und der Draft zwischen Öffnen und Speichern gestartet,
  hätte PostgREST null Zeilen geändert und **keinen** Fehler geliefert — die
  Oberfläche hätte „Gespeichert" gemeldet. Der Filter ist weg. Wann die Zahl
  änderbar ist, entscheidet sichtbar die Oberfläche (`_editable`); was erlaubt
  ist, entscheidet die RLS-Policy „Ersteller verwaltet seine Fantasy-Liga".
  Eine stille dritte Meinung dazwischen half niemandem.
- **Die Zahl kann nicht unter die schon beigetretenen Teams fallen.** Ein
  Limit von 4 in einer Liga mit sechs Teams wäre keine Einstellung, sondern
  ein Widerspruch — die sechs bleiben ja. Der Stepper zieht seine Untergrenze
  deshalb aus `fantasyManagersProvider`, und ein Hinweis nennt den Grund.

**Nach Draft-Start bleibt die Zahl gesperrt**, und das ist kein Versehen:
Migration `0041_post_draft_join.sql` hält ausdrücklich fest, dass die
Team-Anzahl nach dem Draft fix ist. Wer danach beitritt, wird `pending` und
muss vom Admin einem **verwaisten** Team zugewiesen werden
(`fantasy_assign_team`). Ein höheres `max_teams` erzeugte deshalb Plätze, die
niemand füllen kann: Platzhalter sind virtuell und haben keine Mitgliedszeile
(siehe die Notiz zum Slot-Modell). Das zu öffnen heißt, `user_id` nullable zu
machen, einen Surrogatschlüssel einzuführen und `fantasy_assign_team`
umzustellen — eine Migration mit DB-Test, keine Client-Änderung.

## Befehle

```sh
flutter test                               # alle Unit-Tests (Scoring, Parser, Odds)
flutter test test/odds_bonus_test.dart     # eine Datei
flutter test --plain-name "Stufen stapeln" # einzelner Test per Name
flutter analyze
flutter run                                # mit Server — Keys stecken in AppConfig
flutter build ipa                          # TestFlight; braucht keine Flags mehr
flutter build appbundle                    # Google Play (AAB), signiert per key.properties
flutter build apk                          # ein APK zum Sideloaden/Testen
```

**Android-Release.** Drei Dinge, die am Flutter-Template fehlten und ohne die
ein Play-Upload nicht funktioniert — bei Template-Updates nicht wieder
verlieren:

- `INTERNET` steht im **Haupt**-Manifest, nicht nur im Debug-Manifest. Das
  Template gibt die Berechtigung nur Debug/Profile; ein Release-Build käme
  sonst ohne Fehlermeldung nicht an Supabase — dieselbe stumme Falle wie beim
  ersten TestFlight-Build.
- Signiert wird mit dem **Upload-Keystore** `~/keys/matchup-upload.jks`
  (PKCS12, Alias `matchup-upload`, gültig bis 2053). Zugang steht in
  `android/key.properties` (gitignored). Fehlt die Datei, fällt der
  Release-Build absichtlich auf den Debug-Key zurück, damit `flutter run
  --release` weiter geht — ein so signiertes AAB lehnt Play ab. **Keystore +
  Passwort gehören ins Backup:** ohne sie ist kein Update der App mehr
  möglich, nur noch ein Key-Reset über den Play-Support.
- Bei Play App Signing ist das der *Upload*-Key, nicht der Verteilungs-Key;
  Google signiert selbst neu. SHA-256 des Upload-Zertifikats:
  `1D:90:E9:68:C0:F1:7D:CB:F2:97:6F:EC:37:34:5F:84:87:1F:26:85:6E:AC:44:D1:4F:FE:8F:D5:EE:12:B8:D4`.

Vor jedem Upload die Build-Nummer in `pubspec.yaml` (`version: x.y.z+N`)
erhöhen — Play nimmt denselben `versionCode` kein zweites Mal an. iOS und
Android teilen sich diese Nummer.

Toolchain auf dem MacBook: JDK ist die JBR von Android Studio
(`flutter config --jdk-dir=…`), SDK unter `~/Library/Android/sdk` mit
`cmdline-tools/latest`, `platforms;android-36` (= `flutter.compileSdkVersion`)
und akzeptierten Lizenzen. `flutter doctor` muss beim Android-Haken grün sein,
sonst schlägt der Gradle-Lauf mit einer irreführenden Meldung fehl.

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

## Installierte Skills

Zwei Skills liegen in `~/.agents/skills/`, verlinkt nach `~/.claude/skills/` —
also **global**, nicht im Repo. Wer das Projekt frisch auscheckt, hat sie
nicht; sie sind Werkzeug des Arbeitsplatzes, nicht Teil der App.

- **`frontend-design`** (`anthropics/skills`) — eine einzige `SKILL.md`, reiner
  Text, kein ausführbarer Code. Auf Web-Frontends zugeschnitten: Die
  Gestaltungsprinzipien lassen sich übertragen, die Anweisungen zu Markup und
  CSS nicht.
- **`ui-ux-pro-max`** (`nextlevelbuilder/ui-ux-pro-max-skill`) — 5 Python-
  Skripte (~4.000 Zeilen) plus 3,9 MB Datenkatalog, darunter
  `data/stacks/flutter.csv`: **52 Regeln, Stand 13.08.2026, für „flutter
  3.44.x"** — die Version, die hier läuft.

**Zum Risiko von `ui-ux-pro-max`:** Der Installer bewertet ihn mit *Gen: High
Risk* (Socket 0 Alerts, Snyk Low Risk); `frontend-design` steht dort auf
*Safe*. Der Unterschied ist, dass hier ausführbarer Code mitkommt — Skills
laufen mit den vollen Rechten des Agenten. Durchgesehen ergab: keine
Netzwerkzugriffe (`urllib.parse` ist nur String-Zerlegung), kein `subprocess`,
kein `os.system`, kein `eval`/`exec`; gelesen werden die eigenen CSV/JSON-
Dateien, geschrieben wird genau eine Datei, und zwar atomar (Temp-Datei,
`fsync`, `os.replace`) mit einer `safe_slug`-Funktion gegen Path-Traversal.
Gelesen als „enthält ausführbaren Code", nicht als „hier ist etwas Bösartiges".
Wer das Urteil nicht übernimmt, prüft selbst nach — der Befund ist mit
`grep -rE "subprocess|os.system|eval\(|urlopen" ~/.agents/skills/ui-ux-pro-max/scripts`
in einer Minute nachvollzogen.

**Zum Nutzen:** Das Niveau des Flutter-Katalogs ist Grundhygiene („const
constructors", „dispose controllers", „ListView.builder für lange Listen").
Diese Datei hier steht darüber — was der Katalog nicht liefert, ist der Grund,
*warum* etwas so gebaut ist. Als Checkliste taugt er trotzdem. Ein Durchlauf
gegen alle 16 als *High* markierten Regeln (24.08.2026) fand genau eine Lücke:

* `PopScope` statt `WillPopScope`, Controller-Disposal, `ListView.builder` —
  alles sauber.
* **`Semantics` kam in der App kein einziges Mal vor**, und 24 von 43
  `IconButton` hatten keinen `tooltip`. Flutter leitet daraus keine
  Beschriftung ab: Für VoiceOver und TalkBack heißen diese Knöpfe
  „Schaltfläche" — auch das Hamburger-Symbol, der Favoriten-Stern und das „+"
  oben rechts. Seit Juni 2025 ist das für Verbraucher-Apps zudem eine Frage
  des European Accessibility Act, nicht mehr nur des Anstands. Aufgearbeitet:
  erst der Homescreen (siehe unten), dann der Rest der App (siehe
  „Knöpfe brauchen Namen").
* Die Zeile „große Systemschriften — sauber" war **falsch** und ist oben
  gestrichen. Sie stützte sich darauf, dass `textScaler` nirgends angefasst
  wird; genau das ist aber der Grund, warum die Schrift ungebremst wächst —
  und die Karten hatten feste Höhen. Bei 1,3-facher Systemschrift lief der
  Liganame unten aus der Karte, Flutter meldete „RenderFlex overflowed". Ein
  Katalogeintrag prüft die Regel, nicht ihre Folgen; das musste man laufen
  lassen.

**Wo die Apple-Regeln liegen:** nicht im Stack-Katalog. `data/stacks/
swiftui.csv` bringt 50 Regeln, davon sind die meisten SwiftUI-Syntax
(`@State`, Modifier-Reihenfolge) und für Dart wertlos. Die brauchbaren nativen
Regeln stehen in `data/app-interface.csv` — erreichbar ausgerechnet über
`--domain web`, was den Namen zum Stolperstein macht. Von dort kommt die
Regel, die hier am meisten wert war:

> Native targets use 44pt on iOS and 48dp on Android; web WCAG 2.2 has a
> separate 24×24 CSS px minimum. **Don't:** Collapse iOS 44pt, Android 48dp,
> and web 24 CSS px into one cross-platform number.

Deshalb `minTastflaeche(context)` in `home_screen.dart` — **zwei Zahlen, nicht
eine.** Die 24 aus WCAG 2.2 sind die Web-Zahl und taugen hier nicht als
Rechtfertigung für ein kleineres Ziel; die Kopfzeilen tragen jetzt das Maß der
Plattform.

**Was `--design-system` nicht kann:** App-Screens. Zwei Läufe („fantasy sports
league social entertainment mobile", „native app home dashboard dark sports")
geben beide Landingpage-Muster aus — Hero, Feature-Grid, Social Proof,
„Start trial", dazu `cursor-pointer`, Hover-States und Breakpoints bis 1440 px.
Auch `--domain product` liefert ein Feld „Landing Page Pattern", und
`--domain ux` ist eine Korrektheits-Checkliste, keine Quelle für Komposition.
Brauchbar war nur die Bestätigung: Die Palette des zweiten Laufs (`#0F172A`,
Grün `#22C55E`) trifft die Marke fast, und als Stil kommt Glassmorphism heraus
— also das, was `liquid_glass.dart` und die Navileiste ohnehin tun. **Die
Gestaltungsrichtung kommt aus `frontend-design`** (Token-Plan, ASCII-Entwürfe,
eine bewusste Wette), `ui-ux-pro-max` ist der Prüfdurchgang danach.

### Knöpfe brauchen Namen

Alle 24 namenlosen Symbolknöpfe haben einen `tooltip` — den nimmt Flutter
zugleich als Beschriftung für die Vorlesehilfen. Zwei Muster kamen dabei
heraus, beide anderswo wiederverwendbar:

**Blätter-Pfeile nennen ihr Ziel, nicht ihre Richtung.** Sechsmal steht in der
App dieselbe Zeile: ‹ Spieltag 7 ›. Vorgelesen waren das drei Stationen, und
keine sagte, wohin ein Pfeil führt — die Zahl in der Mitte gehört zu keinem
der beiden Knöpfe. Jetzt heißen sie „Zurück zu Spieltag 6" und „Weiter zu
Spieltag 8"; bei Turnieren steht dort der echte Name („Zurück zu
Achtelfinale"), weil `RoundSelector` und `_RoundSelector` die Rundenliste
ohnehin haben. Am Rand der Liste gibt es kein Ziel, dort bleibt „Zurück"
allein stehen. In `league_overview_screen.dart` sind aus den beiden `bool`s
`canPrev`/`canNext` deshalb `String? prevName`/`nextName` geworden: dasselbe
„gibt es sie überhaupt", nur mit der Antwort auf „wohin" darin.

**Bei +/−-Steppern trägt die Zahl den Bezug.** „Exakt getippt" — „Schaltfläche"
— „3" — „Schaltfläche": Beschriftung und Wert standen als getrennte Stationen
da. Wo der Stepper seine Beschriftung selbst rendert (`tip_rules_editor.dart`,
`create_fantasy_league.dart`), sagt sie jetzt beides an („Exakt getippt: 3")
und die Zahl daneben ist `ExcludeSemantics`. Wo die Beschriftung außerhalb
liegt (`fantasy_settings_screen.dart`, in der `_SettingRow`), bleibt die Zahl
eine eigene Station und der Stepper bekommt die Beschriftung als Parameter
gereicht — sie ein zweites Mal an die Zahl zu hängen hätte „Anzahl Runden" in
einer Zeile viermal wiederholt.

Gehalten wird der Stand von `test/knopfnamen_test.dart`: Der Test liest
`lib/` und lässt keinen `IconButton` ohne `tooltip` durch. Ein Widget-Test je
Knopf wäre hier der teurere Weg zur schwächeren Aussage — die meisten dieser
Knöpfe stecken in privaten Klassen, die ohne halben Screen samt Providern
nicht zu rendern sind.

### Systemschrift auf dem Homescreen

Was quer gewischt wird, kann nicht beliebig wachsen: die Liga-Karten stehen
zu knapp vier nebeneinander, ihre Breite ist aus der Bildschirmbreite
gerechnet.
Deshalb sitzt in `_Bleed` ein Deckel (`_kMaxKartenSkala`, 1,3) für alles in
den Reihen, und `kartenHoehe()` lässt die Karte innerhalb dessen **in der Höhe
mitwachsen** — der Deckel allein hätte den Überlauf nur verschoben.

Der Rest des Screens wächst ungebremst weiter: Begrüßung, Vereinszeilen,
Leerzustände und News-Titel stehen längs und haben den Platz. Nur wo Text und
Symbol in einer Zeile stehen, die nicht umbricht — die beiden Knöpfe des
Leerzustands —, liegt der Deckel bei 1,6, und die Höhen sind dort
Mindesthöhen.

### Richtung A — die Zeit führt

Der Startbildschirm folgt einem von drei Entwürfen, die als Design-Canvas
nebeneinander lagen (`design/homescreen/`, publiziert als Artefakt). Die
Diagnose des alten Standes stand darin in fünf Punkten; drei davon sind hier
abgearbeitet, und der Grund ist jedes Mal derselbe: **Was am lautesten war,
trug am wenigsten.**

- Die größte, fetteste Schrift auf dem Schirm war „Hallo, SFV03". Die
  Begrüßung ist jetzt eine graue 15er-Zeile, und die beiden Symbole daneben
  sind entfärbt — Gold und Grün versprachen etwas Anstehendes, wo nichts
  anstand. Der rote Zähler am Nachrichten-Knopf bleibt: der zählt wirklich
  etwas.
- Das nächste Spiel des eigenen Vereins — der emotionalste Inhalt des Schirms
  — bekam eine 46 Punkte hohe Zeile weit unten. Es ist jetzt die **Kopfkarte**
  (`_NaechstesSpiel`): Anstoßzeit als 38er-Zahl mit Tabellenziffern zwischen
  beiden Wappen, darunter der Tag, oben links der Wettbewerb mit Logo. Farbe
  bekommt die Ecke oben rechts nur, wenn etwas ansteht — „HEUTE" in Gold,
  „LIVE" in Rot mit pulsierendem Punkt. Läuft das Spiel, steht statt der
  Uhrzeit das Ergebnis. Die übrigen Partien desselben Tages bleiben unten in
  `_FavoritenSpiele`, das jetzt das erste Spiel überspringt — die Regel
  „alle Spiele des Tages, wenn es mehrere gibt" gilt unverändert, sie ist nur
  auf zwei Stellen verteilt.
  **Oben steht das Spiel des obersten Favoriten**, nicht das früheste des
  Tages: Wer Bayern über Bochum stellt, will an einem Samstag mit beiden
  Bayern auf der Kopfkarte sehen, auch wenn Bochum um 13:30 anfängt.
  `favoritenSpielZuerst` (pur, getestet) hebt es im `favoritenSpieleProvider`
  an den Anfang; der Rest bleibt nach Anstoß sortiert, damit die Liste
  darunter den Tagesverlauf liest. Bei Favorit gegen Favorit zählt der höher
  stehende. Welcher Verein „oben" ist, sagt `favoritenRaenge` — bewusst
  **dieselbe** Regel, die der Favoriten-Tab anzeigt (manuelle Sortierung,
  sonst Liga-Rang, Frauen zuletzt). Sie lag privat in `favorites_tab.dart`
  und ist nach `features/favorites/logic/favorite_order.dart` gezogen: Zwei
  Sortierungen, die beide behaupten, die Favoritenreihenfolge zu sein, laufen
  irgendwann auseinander — und dann steht auf der Kopfkarte ein anderer
  Verein als oben im Favoriten-Tab.
- Vier Farbflächen sagten den Modus an. Siehe oben: aus der Fläche ist ein
  Hauch in der Ecke geworden.

**Was die Kopfkarte bewusst *nicht* trägt: die eigenen Tipps.** Sie hatte
einen Sockel, der je Tipprunde eine Zeile zeigte („Tipptest 1:9",
„BuLi 26/27 2:0"), samt Weg in den jeweiligen Tippen-Tab. Mit zwei Runden
wuchs die Karte um knapp neunzig Punkte und schob alles darunter aus dem
Bild — für eine Auskunft, die der Tippspiel-Abschnitt ohnehin gibt („8 Tipps
offen · bis Sa., 15:30"). Entfernt; die Kopfkarte zeigt das Spiel und sonst
nichts.

Der Abgleich dahinter ist mit ausgebaut worden und steht in der Historie
(`spielTippProvider`, Commit „Die Kopfkarte zeigt jeden Tipp, nicht einen von
mehreren"). Er ist wiederverwendbar, falls der eigene Tipp einmal **im
Spiel-Detail** stehen soll — dort ist Platz, und die Frage „was habe ich hier
getippt" gehört näher ans Spiel als an den Startbildschirm. Sein Kern: Das
Spiel kommt aus dem Vereins-Spielplan, die Tipprunden aus dem Saison-
Spielplan ihrer Wettbewerbe; beide Wege enden bei derselben ID
(`sportmonks:<id>`), der Abgleich ist deshalb exakt und nicht über Namen und
Anstoßzeit geraten.

Der Entwurf hatte an zwei Stellen mehr versprochen, als die Daten hergeben,
und beides ist bewusst nicht nachgebaut: die **Spielstätte** unter der Uhrzeit
(steht nur im Spiel-Detail, ein zweiter Abruf je Spiel wäre der Zeile nicht
wert — dort steht jetzt der Tag) und **Archivo** als zweite Schriftfamilie für
die Zahlen (Barlow Condensed mit `FontFeature.tabularFigures()` tut es; eine
zweite Familie im Bundle ist eine eigene Entscheidung, keine Folge dieser).

Die Kopfkarte hat **zwei** Vorlese-Stationen, nicht eine: das Spiel und der
Sockel führen an verschiedene Orte. Deshalb setzt sie `_PressScale`s
`eineAnsage` ab, das sonst jede Karte zu einer Ansage zusammenfasst.

### Einfarbig ist auch kein Zustand

Der erste Wurf von „Richtung A" nahm die Diagnose zu wörtlich und strich
**alle** Farbe: flache graue Karten, Farbe nur noch dort, wo etwas anstand.
Das Urteil dazu kam in einem Satz — „alles so einfarbig und trostlos" — und es
war richtig. Wer nichts Dringendes offen hat, und das ist der Normalfall, sah
einen Schirm aus lauter dunkelgrauen Rechtecken.

Der Fehler ist benennbar: Die Diagnose hatte die **Hierarchie** angegriffen
(„vier Farbflächen rufen gleich laut und sagen nur den Modus"), nicht die
Farbe. Als Antwort darauf ist Null genauso falsch wie Voll — nur leiser. Was
seitdem gilt:

- **Farbe darf Identität tragen, nicht nur Alarm.** Der Hauch in der
  Kartenecke sagt „das ist diese Liga", der Sockel sagt „hier ist etwas zu
  tun". Zwei verschiedene Aufgaben, zwei verschiedene Stärken — das Problem
  war nie, dass beide Farbe benutzen, sondern dass sie gleich laut waren.
- **Wo Farbe zum Inhalt gehört, ist sie keine Dekoration.** Die Kopfkarte
  bekommt die **Trikotfarben** der beiden Vereine (`core/util/club_colors.dart`,
  bis dahin nur im Spiel-Detail benutzt) — als weicher Hof hinter jedem
  Wappen. Rot links heißt Bayern, und das sieht man vor dem Namen. Über die
  ganze Karte gezogen war es falsch: Bayern gegen Stuttgart sind zwei rote
  Vereine, das ergab eine durchgehend rote Fläche. Die Farbe klebt am Verein,
  nicht an der Karte, und die Mitte bleibt neutral, weil dort die Uhrzeit
  steht. `vereinsTon()` weicht dabei auf `secondary` aus, wenn die Grundfarbe
  fast weiß oder fast schwarz ist (Stuttgart, Gladbach, Frankfurt) — und gibt
  `null` für unbekannte Vereine zurück: eine erfundene Farbe für einen
  Pokalgegner aus der Oberliga sähe aus wie eine Auskunft.
- **Fünf gleiche graue Versalköpfe geben keinen Takt** (Punkt 5 der
  Diagnose, zuerst übersehen). Jeder Abschnittskopf trägt jetzt einen 3 px
  breiten Strich in der Farbe seines Bereichs: Grün für die Ligen, Gold fürs
  Tippspiel, Blau (`_kVereinsBlau`) für Vereine und News. Die kleinste Menge
  Farbe, die trennt — und sie wiederholt nur, was im Abschnitt darunter
  ohnehin vorkommt.
- **Ein Leerzustand ist eine Einladung, kein abgeschalteter Bereich.** Die
  `_CreateRow` war ein grauer Umriss unter einem grauen Kopf und sah aus wie
  etwas, das nicht geht. Sie trägt jetzt die Farbe des Bereichs, in den sie
  führt.

### „Tinntest" — wenn zu wenig Höhe den Namen frisst

Ein Fehler, der sich nirgends meldete und trotzdem Text zerstörte: Auf der
Tipprunden-Karte stand „Tipptest", zu lesen war „Tinntest". Beide
`p`-Unterlängen waren abgeschnitten.

Die Ursache lag nicht bei der Schrift, sondern in der Kartenhöhe. Der
`_KartenSockel` ist ein- **oder zweizeilig** („Draft läuft" über „Pick 1",
„18 Tipps offen" über der Frist). Mit der einzeiligen Fassung ging das alte
Maß auf; mit der zweiten Zeile fehlten rund fünf Punkte. Die nahm sich der
`Flexible` um den Namen — nicht der Untertitel darunter, der ist nicht
flexibel. Statt 17 bekam der Name 12,1 Punkt, und was nicht hineinpasste,
wurde weggeschnitten. **Kein Überlauf, keine Warnung, kein gelb-schwarzer
Balken:** Für Flutter war das eine gültige Anordnung. Sichtbar wurde es erst
an einem Namen mit Unterlängen — und nur an dem, weshalb Wochen mit
„Draftest3" und „BuLi 26/27" nichts auffiel.

Drei Dinge folgen daraus:

- Die Kartenhöhen tragen jetzt den **zweizeiligen** Sockel (`_kLeagueCardHeight`
  146, `_kTipCardHeight` 140), mit Reserve.
- `height: 1.05` an der Namenszeile war ohnehin knapper als die Schrift: Barlow
  Condensed braucht bei 14 Punkt rund 16,8. Steht jetzt auf 1,2.
- `test/home_vorschau_test.dart` hält den Stand mit einer Messung statt mit
  einem Bild: Jeder Kartenname muss mindestens eine volle Zeile hoch sein. Ein
  Golden hätte den Fehler nicht gefangen — er sah ja aus wie ein Wort.
  Deshalb steht in der Vorschau ein Name mit Unterlängen („Tipptest",
  „Übungsliga") und ein Sockel mit Frist.

### Den Homescreen ansehen, ohne auf den eigenen Account angewiesen zu sein

`test/home_vorschau_test.dart` rendert den **ganzen** Screen mit gesetzten
Zuständen nach `test/goldens/home_vorschau.png`:

```sh
flutter test --update-goldens test/home_vorschau_test.dart
```

Der Anlass war handfest: Bei der Abnahme von „Richtung A" hatte der
Testaccount keine eigenständige Tipprunde, also war der komplette neue
Zeilen-Abschnitt im Simulator nicht zu sehen — und ein zweiter Screenshot
hätte daran nichts geändert. Drei Dinge, die dabei zu wissen sind:

- **`AppConfig.supabaseInitialized = true` setzen**, sonst hält der Screen
  sich für serverlos und zeigt statt allem eine Hinweiskarte.
- **Die Gerätegröße über `tester.view` setzen, nicht über
  `setSurfaceSize`.** Letzteres ändert nur, worauf gezeichnet wird; die
  `MediaQuery` bleibt bei 800×600. Fast überall egal — aber `_Bleed` und
  `leagueCardWidth` rechnen ihre Maße genau daraus, und dann steht eine 800
  breite Kartenreihe hinter einem 402 breiten Bild.
- **Kein `pumpAndSettle`.** Die Draft-Anzeige pulsiert endlos, der Aufruf
  liefe in den Timeout; stattdessen ein paar feste `pump`-Schritte.

Material-Symbole werden darin zu leeren Kästchen und Wappen zu Ersatzflächen
(nur die App-Schrift wird geladen, Netz gibt es im Test keins). Verglichen
wird die Anordnung, nicht das Bild.

## Live-Tab — „B, Tafel"

Wie beim Startbildschirm lagen drei Richtungen als Design-Canvas nebeneinander
(`design/live/`, publiziert als Artefakt), dazu die Diagnose des alten Standes
in sechs Punkten. Gewählt wurde **B — Tafel**: eine durchgehende Fläche statt
Karten.

Was sich daraus geändert hat:

- **Kein Titel „Live" mehr.** Er war die größte Schrift des Schirms für eine
  Auskunft, die die Navileiste gibt. Die Kopfzeile trägt jetzt den **gewählten
  Tag**, rechts daneben steht, was gerade läuft („2 live", pulsierender Punkt).
  Läuft nichts, bleibt die Seite leer — „0 live" wäre eine Meldung über nichts.
- **Keine Liga-Karten.** Je Wettbewerb eine **Kapitelmarke** (`_LigaKopf`):
  Wappen, Name, und eine Haarlinie bis an den rechten Rand; darunter die
  Spiele. Der Liganame steht **nicht** in der Ligafarbe — fünf farbige
  Überschriften untereinander riefen gleich laut, und die Farbe sagt ohnehin
  das Wappen. So bleibt Farbe für das übrig, was läuft.
  Der erste Entwurf war ein getöntes Band über die volle Breite, und das war
  an drei Stellen falsch: Die Tönung auf 3 % Deckung war weder Fläche noch
  nichts, nur ein Grauschleier, der die Tafel in Streifen zerschnitt; der Name
  in gesperrten Versalien sah aus wie eine Systembeschriftung; und die Anzahl
  rechts war der **dritte** Ort, an dem derselbe Wettbewerb angesagt wurde —
  genau der Vorwurf, mit dem der alte Live-Tab in die Überarbeitung ging, hier
  unbemerkt wieder eingebaut.
  **Fallstrick an der Linie:** `Flexible` hat standardmäßig `flex: 1`. Neben
  einem `Expanded` teilt sich der Name den freien Platz dann hälftig mit der
  Linie, und die endet mitten im Nichts statt am Rand. Der Name steht deshalb
  in `Flexible(flex: 0)` — natürliche Breite, darf trotzdem schrumpfen.
- **Die Spielzeile** (`_SpielZeile`): Wappen außen, der Name **direkt daneben
  an der Außenkante**, Ergebnis oder Anstoß in der Mitte, der Live-Punkt ganz
  außen. Der 4-px-Streifen links ist weg — er verschob die Zeile gegen die
  anderen. Laufende Spiele sind rot getönt und tragen das Ergebnis in Rot.
  Zuerst waren die Namen **zur Mitte hin** ausgerichtet, also an das Ergebnis
  gedrängt; die Zeile sah dadurch in der Mitte zusammengeschoben aus, und
  neben den Wappen klaffte bei jeder Zeile eine andere Lücke — bei „RB
  Leipzig" eine große, bei „Borussia Mönchengladbach" keine. Über mehrere
  Zeilen ergab das einen unruhigen linken und rechten Rand. Jetzt fluchten die
  Spalten, und der Luftraum sammelt sich um das Ergebnis, wo er nicht stört.
- **„Anstoß" unter der Uhrzeit ist gestrichen** — das sagte dasselbe zweimal,
  derselbe Fehler wie „bis 20:30" unter einer 20:30. „beendet" bleibt: Einem
  3:2 sieht man nicht an, ob es das Endergebnis ist.
- **Die Wettbewerbe sind fünf gleich breite Kacheln** (`_WettbewerbsKacheln`)
  — alle ohne Wischen sichtbar und direkt antippbar. Drei Fassungen hat das
  gebraucht, und die mittlere ist die lehrreiche: Zuerst fünf farbige
  Textknöpfe in zwei Reihen (rund 90 Punkte Dauerbild, fünf Signalfarben als
  Schrift). Dann eine einzelne Zeile „Wettbewerbe", die die Auswahl hinter ein
  Sheet legte — ruhig, aber **ein Tipp mehr für etwas, das man auf einen Blick
  treffen können soll**; zurückgedreht auf Ansage. Jetzt Kacheln: Das Wappen
  trägt die Erkennung, die Farbe sitzt in Tönung und Kante statt in der
  Schrift, die Beschriftung steht ruhig darunter (`_kurzerName`: „2. Liga",
  „Pokal", „Frauen" — die vollen Namen passen bei knapp 72 Punkten je Kachel
  nicht). Gleich breit, weil sonst „Bundesliga" die Reihe dominiert und
  „Pokal" den Restplatz bekommt.

**Zwei bewusste Abweichungen vom Entwurf**, beide dokumentiert, weil sie sonst
wie Nachlässigkeit aussehen:

- Der Entwurf ließ die **Wappen** weg (dichter, ruhiger). Sie sind geblieben,
  klein und außen: Sie tragen das Wiedererkennen auf einen Blick, und über sie
  führt der **einzige** Weg vom Live-Tab auf eine Vereinsseite (`ClubLink`).
  Ohne sie wäre der still verschwunden.
- Die **Punkte in der Tagesleiste** standen nur in Richtung A. Sie sind
  trotzdem hier, weil sie einen eigenen Diagnosepunkt erledigen: Fünfzehn
  gleiche Zellen sagten nicht, an welchem Tag überhaupt gespielt wird. Jetzt
  hat jeder Spieltag einen Punkt, rot, wenn dort etwas läuft, und Tage ohne
  Spiele stehen gedimmt. Ausgewählt ist hell statt grün — auf einer Tafel,
  deren einzige Farbe „hier läuft etwas" heißt, wäre ein grüner Klotz ein
  Signal ohne Anlass.

**Nicht entworfen: die Spielminute.** `FixtureStatus` kennt nur `scheduled`,
`live`, `finished` — der Feed liefert keine Minute. Ein „67.'" wäre ein
Versprechen, das die Daten nicht halten; wer es will, klärt das zuerst mit
Sportmonks.

- **Die Spielzeile ist bewusst groß**: Wappen 22, Namen 15,5, Ergebnis 19.
  Die Namen **schrumpfen statt zu kappen** (`FittedBox`, dieselbe Regel wie
  beim Wettbewerb auf den Homescreen-Karten) — auf einer Ergebnistafel ist der
  Verein der Inhalt, und „Bor. Mönchengladb…" wäre keiner. Es trifft nur die
  zwei, drei längsten Namen.

Angesehen wird der Tab über `test/live_vorschau_test.dart`: Auf dem Gerät
zeigt er nur, was der Kalender gerade hergibt — an einem spielfreien Mittwoch
nichts.

**Der Bildvergleich beider Vorschauen (Home und Live) läuft nur mit
`--update-goldens`.** Beide Schirme benutzen intern `DateTime.now()` — der
Live-Tab wählt beim Öffnen heute, die Kopfkarte schreibt das Datum ihres
Spiels hin. Ein fest eingecheckter Vergleich ist damit **am nächsten Tag
rot**, und das ist genau einmal passiert. Ein Test, der täglich rot wird,
bringt niemandem etwas außer der Gewohnheit, ihn zu übergehen. Die Bilder sind
zum Ansehen da; was gehalten werden muss, steht als **Messung** daneben (etwa
die Zeilenhöhe der Kartennamen) und läuft bei jedem `flutter test`.

## Liga-Übersicht — „C, das Duell führt"

Fünfter Schirm nach demselben Verfahren (`design/liga-uebersicht/`).
**Besonderheit:** Dieser Screen sieht in drei Phasen verschieden aus — Aufbau,
Draft, Saison. Richtung C beschreibt nur die Saison; für die beiden anderen
Phasen ist Richtung A umgesetzt, sonst hätte der Schirm in zwei von drei
Zuständen keinen Kopf.

- **In der Saison führt das eigene Duell** (`MatchupHero`, gab es schon). Im
  Aufbau und im Draft steht dort `_NaechsterSchritt`: **ein** Auftrag, groß,
  mit dem Knopf dazu — „Noch 7 Plätze frei · Spieler einladen / Draft
  starten", „Der Draft läuft · Zum Draft". Vorher stand dort eine 165 Punkte
  hohe Zustandskarte („Setup") mit halbtransparentem Dekor-Chevron, die nicht
  antippbar war; was zu tun ist, steckte hinter einer Kachel weiter unten. Ein
  Zustand ist kein Auftrag.
- **„Schnellzugriff" ist weg** — die Rubrik über zwei gefüllten Kacheln. Es
  sind zwei Zeilengruppen geworden: **Mein Team** (Aufstellung, Free Agency,
  Trades) und **Liga** (Draft-Raum, Tippspiel, Chat, Einladen), jeweils unter
  einer Kapitelmarke, mit leisem Zusatz rechts („läuft", „3 dabei") und rotem
  Zähler nur da, wo etwas wartet.
- **Der grüne Reiterbalken ist weg.** `SegmentedTabBar` steckt an acht Stellen
  in der App und bleibt dort; hier steht `LeiseReiter`
  (`app/widgets/leise_reiter.dart`), gemeinsam mit dem Favoriten-Tab. Die
  Reiter-Symbole sind mit entfallen — vier Wörter nebeneinander brauchen keine
  Piktogramme.
- **Der Spieltag benutzt die gemeinsame Zeilenform** (`fixturesWithDateHeaders`).
  Er kam als `Fixture` und wird dafür auf `TeamFixture` gedreht — dieselben
  Felder, anderer Einstiegspunkt in dieselben Daten. Drei Darstellungen
  derselben Liste waren zwei zu viel.

Für diesen Schirm gibt es **keine** Golden-Vorschau: Er hängt an einem Dutzend
Provider (Kader, Aufstellungen, Spielerpool, Saison-Fixtures, Trades, Manager),
und die Diagnose stand auf einem Gerätebild. Wer ihn ändert, sieht ihn sich am
Gerät an.

## Seitenmenü — „B, das Menü trägt Inhalt"

Vierter Schirm nach demselben Verfahren (`design/seitenmenue/`), gewählt wurde
**B**: Das Menü beantwortet beim Öffnen die Frage, für die man es aufmacht —
**wer will was von mir?**

- **Offene Freundschaftsanfragen und die letzten Gespräche stehen darin**, mit
  Namen und Vorschautext, höchstens drei je Abschnitt (`_maxZeilen`); darunter
  „Alle Anfragen"/„Alle Chats". Mehr würde aus dem Menü einen zweiten
  Chat-Screen neben dem echten machen.
- **Kein Grün mehr.** Vorher trugen drei Icon-Kacheln und der Ring um den
  Avatar das Markengrün — obwohl Grün in dieser App „hier läuft etwas" heißt
  und dort nichts lief. Schlimmer: Die echten Signale (rote Zahl, roter Punkt)
  standen direkt daneben und mussten dagegen ankommen. Jetzt hat nur Farbe,
  was wartet: „2 neu" an der Abschnittsmarke, ein roter Punkt je Zeile.
- **Der Eintrag „Profil" ist entfallen** — er stand für dasselbe Ziel wie der
  Kopf darüber ein zweites Mal. Der Kopf heißt jetzt „Profil & Einstellungen".
- **Die Abschnittsmarke ist dieselbe wie im Live- und Favoriten-Tab** (Wort,
  Haarlinie bis an den Rand, rechts der Hinweis auf Offenes). Ein Menü ist kein
  Grund für ein eigenes Gliederungsmuster.
- **Leere Abschnitte fallen auf schlichte Zeilen zurück** („Freunde
  verwalten", „Nachricht schreiben"). Eine Überschrift mit nichts darunter
  wäre schlimmer als der alte Zustand.

Damit lädt das Menü **Daten** — vorher war es reine Navigation. Es zeigt, was
da ist, und wartet nicht: Fehlen Namen oder Bilder noch, stehen die Zeilen mit
dem, was schon bekannt ist.

Angesehen wird es über `test/seitenmenue_vorschau_test.dart`. Der
Bildvergleich ist hier **fest** eingeschaltet — anders als bei den drei
Schirmen steht im Menü kein Datum, das Bild ist von Tag zu Tag gleich. Der
Test braucht `SharedPreferences.setMockInitialValues({})`, weil der
Ungelesen-Punkt je Gespräch seine Lesemarke von dort holt.

## Favoriten-Tab — „A, der Verein führt""

Dritter Schirm nach demselben Verfahren: Diagnose plus drei Richtungen als
Design-Canvas (`design/favoriten/`), gewählt wurde **A**.

- **Kein Titel „Favoriten"** — er war die größte Schrift des Schirms für eine
  Auskunft, die die Navileiste gibt. Den Kopf bildet die **Wappenreihe**
  selbst: das gewählte Wappen 52 Punkte und voll deckend, die übrigen 40 und
  auf 55 % zurückgenommen. **Ohne Beschriftung** — vorher trugen 32er-Wappen
  eine 9,5-Punkt-Zeile, in der „Borussia Dortmund" zweizeilig umbrach;
  ausgerechnet die wichtigste Auswahl des Schirms war sein Kleinstes. Am Ende
  der Reihe sitzen die beiden Aktionen (sortieren, hinzufügen) als runde
  Knöpfe.
- **Der Vereinsname ist die Überschrift**, darunter Wettbewerb und
  Tabellenplatz („Bundesliga · Platz 12"). Der Platz kommt über die
  **Team-ID** aus `leagueTableProvider`, nicht über den Namen: „1. FC Köln"
  und „FC Köln" stehen in denselben Daten nebeneinander, ein Namensvergleich
  träfe mal und mal nicht. Fehlt die Tabelle (Pokal, Saisonstart, noch am
  Laden), bleibt es beim Wettbewerb allein.
- **Der Reiter ist eine leise Textumschaltung** mit Unterstrich. Vorher lag
  dort eine ganze Zeile in Signalgrün — das lauteste Element des Schirms, um
  zwei Optionen anzusagen. Grün heißt in dieser App „hier läuft etwas"; ein
  Reiter läuft nicht.
- **Die Spiele sind Zeilen statt Karten**, und zwar dieselben wie im Live-Tab:
  Wappen an den Außenkanten, Namen direkt daneben, Uhrzeit oder Ergebnis in
  der Mitte. Vorher stand es genau andersherum (Wappen innen, Namen außen) —
  zwei Schirme, die dieselbe Liste zeigen, fluchteten nicht miteinander.
  Datum, Wettbewerb und Spieltag stehen in **einer** Zeile darüber; vorher
  ergaben vier Spiele acht Blöcke, weil das Datum über der Box stand und
  Wettbewerb plus Spieltag noch einmal darin.

**Das trifft die Vereinsseite mit** (`club_screen.dart`): Sie benutzt
`fixturesWithDateHeaders`/`TeamFixtureCard` aus `app/widgets/`. Bewusst nicht
abgekoppelt — zwei Darstellungen derselben Liste wären beim nächsten
Feinschliff sofort wieder auseinandergelaufen.

Angesehen wird der Tab über `test/favoriten_vorschau_test.dart`; wie bei den
anderen beiden Vorschauen läuft der Bildvergleich nur mit `--update-goldens`.

## Startbildschirm

Zwei Schirme hintereinander, und nur der zweite lässt sich animieren:

1. **Nativ** (`ios/Runner/Base.lproj/LaunchScreen.storyboard`) — zeigt das
   Betriebssystem, bevor Flutter läuft. Statisch, nicht animierbar. Das
   `LaunchImage`-Asset ist deshalb **absichtlich leer** (1×1 transparent);
   sichtbar ist nur die Hintergrundfarbe, dieselbe wie `MatchUpColors.base`.
   Stünde dort wieder das Logo, sähe man es erst fertig, dann verschwinden
   und in der Flutter-Animation neu einfliegen.
   **iOS merkt sich den Startbildschirm.** Ein `flutter run` über die
   installierte App zeigt weiter den alten — erst
   `xcrun simctl uninstall <udid> app.matchup.mobile` (bzw. App löschen)
   räumt den Zwischenspeicher. Wer eine Änderung daran prüft, ohne vorher zu
   deinstallieren, misst den alten Stand. Achtung: das löscht auch die
   Anmeldung im Simulator.
2. **Flutter** (`app/widgets/matchup_splash.dart`) — die grüne Markenhälfte
   fährt von oben ein, die rote von unten, sie treffen sich in der Mitte,
   dann erscheint die Wortmarke. Steht der Schirm danach und wartet auf
   Daten, läuft eine Welle aus drei Punkten in den Markenfarben von links
   nach rechts (der aktive streckt sich zur Kapsel) — sonst wäre nicht zu
   unterscheiden, ob geladen wird oder etwas hängt. Ein Tipp überspringt.

Die App wird **erst gebaut, wenn der Schirm weggeht** — nicht schon nach dem
Intro. Animation und Aufbau teilen sich denselben Thread, und der Aufbau des
Homescreens hält ihn im Debug-Build sekundenlang an. Baut die App früher,
friert ausgerechnet die Ladeanzeige ein, während geladen wird. Solange
gewartet wird, gehört der Thread der Animation; abgeblendet wird erst im
Frame **nach** dem Aufbau (`addPostFrameCallback`), sonst ruckelt die
Überblendung genauso.

Danach **bleibt der Schirm stehen, bis `homeBereitProvider` wahr ist** (Ligen
und Tipprunden geladen; News, Favoritenspiele und offene Tipps füllen sich
danach sichtbar auf — an die langsamste Quelle darf der Startschirm nicht
gehängt werden). Weil er damit an fremden Daten hängt, gibt es eine
Notbremse von 8 Sekunden; danach wird abgeblendet, komme was wolle. Ein Tipp
überspringt.

Der Text darin steht in einem `Material`. Ohne das zeichnet Flutter Text
ohne Unterlage mit dem gelben Doppelstrich — das sah wie ein Designfehler
aus, war aber der eingebaute Hinweis „missing Material widget".

Im Debug-Build auf dem Simulator dauert der Aufbau sichtbar lange;
**Release/Profile lassen sich auf dem iOS-Simulator nicht starten**
(„Releasemode is not supported by iPhone 17 Pro"), gemessen ist der echte
Ablauf also nur auf einem Gerät.

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
  **Hot-Restart schreibt den Code nicht in die installierte App.** Er landet
  in einem Wegwerf-Ordner (`…/Data/Application/<id>/tmp/…/main.dart.dill`),
  auf den nur die laufende `flutter run`-Sitzung zeigt; das Bundle
  (`Runner.app/…/flutter_assets/kernel_blob.bin`) bleibt auf dem Stand des
  letzten Builds. Stirbt die Sitzung und startet die App kalt, läuft wieder
  der alte Code — für den, der draufschaut, sieht das aus, als wäre die
  Arbeit verschwunden. Daraus zwei Regeln:
  * Nach einer abgeschlossenen Änderung einmal **neu installieren**
    (`flutter run` neu starten), nicht nur hot-restarten. Ob es gewirkt hat,
    zeigt der Zeitstempel von `kernel_blob.bin` — der muss neu sein.
  * **`Lost connection to device` heißt nicht „App tot"**, sondern „ab jetzt
    zeigt sie alten Code". Die App läuft weiter (im Simulator per
    `xcrun simctl spawn <udid> launchctl list | grep matchup` sichtbar), nur
    hängt niemand mehr am anderen Ende. Häufigster Auslöser: das MacBook war
    im Ruhezustand.
  Screenshots aus einer laufenden Sitzung belegen deshalb nur, dass der Code
  **im Speicher** stimmt — nicht, dass er auf dem Gerät liegt.
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
- **Android-Emulator (Gegentest vor einem Play-Upload):** AVD `matchup_pixel`
  (Pixel 7, Android 36, arm64). Steuerung geht hier zuverlässiger als im
  iOS-Simulator, weil `adb` Taps und Text direkt annimmt:
  ```sh
  ~/Library/Android/sdk/emulator/emulator -avd matchup_pixel -no-boot-anim \
    > /tmp/emulator.log 2>&1 < /dev/null & disown
  adb wait-for-device && adb install -r build/app/outputs/flutter-apk/app-release.apk
  adb shell am start -n app.matchup.mobile/.MainActivity   # nicht `monkey`, s. u.
  adb exec-out screencap -p > /tmp/android.png
  adb shell input tap X Y; adb shell input text "…"; adb shell input keyevent 61  # 61 = TAB
  ```
  **Direkt nach `adb install` scheitert ein Start per `monkey`** („VM exiting
  with result code -5"): der Paketmanager ist eine Sekunde später fertig als
  das `Success`. `am start` benutzen, das sieht wie ein Absturz aus, ist aber
  keiner. **Zwischen zwei Feldern per TAB wechseln, nicht per Tap** — die
  Tastatur schiebt das Layout hoch, ein Tap auf die vorher notierte Koordinate
  landet dann im falschen Feld.
  Ob der Release-Build wirklich am Server hängt, zeigt eine Anmeldung mit
  Fantasie-Daten: „E-Mail oder Passwort ist falsch" kommt von Supabase, ist
  also der Beweis für den Round-Trip (und damit für die `INTERNET`-Berechtigung).
- **Web-Demo:** mit dem Build-/Deploy-Ablauf oben neu nach `gh-pages` pushen
  und live verifizieren (md5 von `main.dart.js` gegen den Build vergleichen;
  GitHub Pages propagiert ~15–60 s).
