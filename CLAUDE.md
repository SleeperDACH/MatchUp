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
- **Live-Punkte hängen an drei Gliedern, und alle drei müssen laufen.** Am
  28.08.2026, während des ersten Saisonspiels, zeigte die App keine Punkte —
  weil `player_match_stats` **komplett leer** war. Die Kette und ihre Fallen:
  * **Die Function muss deployed sein.** `sync-stats` lief seit Juni alle 15
    Minuten, 7545-mal „succeeded" — und schrieb nie eine Zeile. In
    `net._http_response` stand `{"season":2026,"rounds":[],"upserted":0}`, eine
    Antwortform, die es im Repo gar nicht gibt (dort `{fixtures, upserted}`).
    Deployed war eine **ältere** Fassung, die über „Runden" lief; die
    fixture-basierte im Repo war nie ausgespielt worden. Exakt dieselbe Falle
    wie bei `sync-squads`. **`supabase functions list` zeigt, was wirklich
    draußen ist — die Datei im Repo beweist gar nichts.**
  * **Der Takt muss zum Wort passen.** Alle 15 Minuten ist für ein laufendes
    Spiel keine Anzeige, sondern ein Archiv. Migration 0080 stellt auf
    Minutentakt; das ist billig, weil die Function zuerst die eigene
    `fixtures`-Spiegelung fragt und **ohne einen einzigen Sportmonks-Request**
    umkehrt, wenn nichts läuft. Kosten entstehen nur im Spielfenster (~90
    Requests je Spieltag von 2000).
  * **Der Client muss hinsehen.** `roundStatsProvider` war ein einfacher
    `FutureProvider`: einmal geladen, nie wieder. Die Punkte standen auf dem
    Stand beim Öffnen des Schirms. Er lädt jetzt alle 30 s nach, **solange der
    Spieltag läuft** (`roundIsLiveProvider`), und stellt außerhalb der
    Spielfenster gar keinen Timer. Ein einmaliger `Timer` statt
    `Timer.periodic` — nach dem Neuladen baut der Provider sich ohnehin neu auf
    und stellt den nächsten. Die Spielpläne werden mit aufgefrischt, sonst
    bliebe die Runde nach dem Abpfiff für immer „live".
  Dass der Server schreibt, heißt nicht, dass die App es zeigt; dass ein Cron
  „succeeded" meldet, heißt nicht, dass etwas ankam.
- **Jeder `net.http_post`-Cron braucht `timeout_milliseconds`.** Der
  pg_net-Standard ist 5000 ms, und `cron.job_run_details` meldet trotzdem
  „succeeded" — der Fehlschlag steht nur in `net._http_response`
  (`timed_out`, `status_code`). `sync-fixtures` lief deshalb in **jedem**
  Durchgang ins Limit (37 von 37 Läufen in sechs Stunden), ohne dass es
  irgendwo aufgefallen wäre; Migration 0081 setzt Zeitlimit und Vault nach.
  Prüfregel bei jedem neuen Job: `select jobname, command like '%timeout%',
  command like '%vault%' from cron.job` — beides muss wahr sein.
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
  und −0,4 je Foul. Für die Anzeige `formatPoints()` benutzen, **immer**.
  `0.4` ist binär nicht exakt darstellbar; dreißig Klärungen à 0,4 ergeben
  `12.100000000000001`, und genau das stand im „Team der Woche" auf dem
  Schirm. Gefunden an einer Stelle, gefixt an **fünfzehn**: Der Fehler steckte
  quer durch den Fantasy-Bereich (Recap, Duell-Kopf, Playoff-Baum,
  Aufstellungen, Manager-Profil, Tabelle, Spielfeld und Bank) — überall
  dieselbe Zeile `Text('$points')`.
  Gehalten wird das von `test/punkte_formatierung_test.dart`: Der Test liest
  `lib/features/fantasy/ui/` und lässt keine String-Interpolation durch, die
  „points" enthält und nicht durch `formatPoints()` läuft. Ausnahmen stehen
  dort namentlich mit Grund — `record.points` in der Fantasy-Tabelle ist ein
  `int` (Ligapunkte aus Siegen), kein Score. Diese Unterscheidung hat übrigens
  der Analyzer erzwungen: `formatPoints(int)` kompiliert nicht, der eine
  falsche Treffer fiel beim ersten Durchlauf sofort auf.
  Eine Nachkommastelle genügt und ist **exakt**: Alle Werte der Wertung sind
  Vielfache von 0,1, und angezeigt werden ausschließlich Summen, keine
  Durchschnitte.
  Ligen, die vor der Umstellung angelegt wurden, tragen in
  `fantasy_leagues.scoring` noch das alte 6-Kategorien-Objekt ohne `version`;
  `FantasyScoringRules.fromJson` gibt für die bewusst die Standardwertung
  zurück, statt alte Zahlen in die neue Wertung zu übernehmen.
  **Es sind in Wahrheit drei Stellen**, und die dritte hat gebissen: Die
  Draft-Rangliste in `fantasy_autopick_if_expired` liest dieselbe JSONB in SQL.
  Sie castete die Werte mit `::int` — und `'12.0'::int` ist in Postgres kein
  Rundungsfehler, sondern `22P02 invalid input syntax for type integer`. Seit
  v2 stehen dort Kommazahlen (`assist: 12.0`), also warf die Funktion in jeder
  v2-Liga bei jedem Aufruf. Alte Ligen (`version: null`, Werte `3`/`-1`/`-3`)
  liefen weiter — deshalb fiel es monatelang nicht auf. Migration 0079 rechnet
  in `numeric`, liest die v2-Schlüssel (die alten `appearance`, `goalGk…` und
  `cleanSheetGkDef` gibt es in v2 gar nicht mehr, die Rangliste sortierte für
  neue Ligen still nach den Gewichten des alten Modells) und holt jede Zahl
  über `public.fantasy_num`, das bei unlesbaren Werten den Vorgabewert liefert
  statt zu werfen. Zwei Werte stehen dabei fest in der SQL, weil `toJson()` sie
  nicht serialisiert: Einsatz 10 und Zu Null 12. **Wer sie in der Wertung
  ändert, ändert sie dort mit.**
  Unsichtbar blieb der Fehler zehn Minuten lang wegen der Client-Seite: Der
  Draft-Raum rief den RPC im Sekundentakt und hängte nur ein `whenComplete`
  an — ein **Future ohne Zuhörer**. Der Fehler landete nirgends, und der Raum
  sah bei einem kaputten Server exakt so aus wie bei Ruhe: Uhr läuft ab, nichts
  passiert. Der Aufruf trägt jetzt ein `onError`, und klemmt der Auto-Pick,
  steht die Ursache als rote Zeile im Raum (`_AutopickWarnung`). Für alles,
  was **automatisch im Hintergrund** läuft, gilt dasselbe: Wenn es die
  Notbremse einer Sache ist, darf sein Fehlschlag nicht stiller sein als sein
  Erfolg.
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

Der Weg dorthin war: `signUp` legte Konto und Profil in **zwei** Schritten an.
Ging der zweite schief — etwa weil der Nutzername vergeben ist (23505) —,
blieb das Konto stehen. Ein zweiter Versuch mit anderem Namen scheiterte an
„Für diese E-Mail existiert bereits ein Konto", und der Betroffene saß fest.

**Seit Migration 0078 entsteht das Profil in der Datenbank**, per Trigger auf
`auth.users` (`profil_fuer_neues_konto`). Damit hängt die Garantie nicht mehr
an App-Version, Anmeldeweg oder daran, ob der Client seinen zweiten Schritt
schafft. Drei Dinge folgen daraus:

* **`signUp` macht jetzt ein `update`, kein `insert`.** Die Zeile gibt es
  schon; ein `insert` liefe gegen den Primärschlüssel. Misslingt das Update,
  steht trotzdem ein gültiges Profil da — der Nutzer kommt in seine Ligen und
  ändert den Namen im Profil.
* **Die Namensregel steht zweimal** — in `username_vorschlag.dart` und als
  `public.profil_namensbasis`. Das ist dieselbe Sorte bewusster Doppelung wie
  bei `tip_scoring.dart` ↔ SQL-View: Der Client braucht sie für seinen
  Vorschlag im laufenden Betrieb, die Datenbank für die Garantie. **Wer eine
  ändert, ändert die andere mit.**
* Der Trigger verschluckt seinen eigenen Fehler (`exception when others`):
  Lieber ein Konto, das der Client nachheilt, als eine Registrierung, die an
  einem Profil scheitert.

Nachgemessen am 27.08.2026 über den echten Weg (`POST /auth/v1/signup` plus
`PATCH /rest/v1/profiles`): Der Trigger legt aus `probelauf0078@…` das Profil
`probelauf0078` an, der Client setzt danach den Wunschnamen; bei zwei Konten
mit gleicher Namensbasis zählt der Trigger auf `…2` hoch.

Zwei weitere Änderungen fangen ab, was trotzdem durchrutscht:

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

## Fantasy-Einstellungen

Kein eigener Canvas — der Schirm bekommt die Sprache, die die anderen fünf
inzwischen sprechen. Drei Befunde, drei Änderungen:

- **Neun grüne Symbole untereinander.** Jede Zeile trug `scheme.primary`,
  obwohl Grün in dieser App „hier läuft etwas" heißt und in einer
  Einstellungsliste nichts läuft. Jetzt hat **jede Gruppe eine Farbe** (Liga
  grün, Mein Team türkis, Regeln & Format gold, Admin blau, Gefahrenzone rot),
  und dieselbe Farbe steht im Strich des Gruppenkopfs. Die Farbe gliedert,
  statt neunmal dasselbe Signal zu geben.
- **Die Gruppenköpfe waren 11-Punkt-Versalien in Grau**, kaum von den
  Untertiteln zu unterscheiden. Jetzt dieselbe Kapitelmarke wie überall sonst:
  farbiger Strich, Wort, Haarlinie bis an den Rand.
- **Titel und Untertitel waren fast gleich groß.** Titel jetzt 16, Untertitel
  12,5 und leiser; die Zeilen sind nicht mehr `dense`.

Zwei Fallen, beide beim Nachsehen im Bild aufgefallen und nicht im Code:

- **Ein blankes `TextStyle` erbt die `fontFamily` nicht.** `titleTextStyle:
  TextStyle(...)` in `ListTileThemeData` ersetzt den aufgelösten Stil; die
  Zeilen fielen auf Roboto zurück statt Barlow Condensed zu benutzen — auf dem
  Gerät genauso wie in der Vorschau. Die Stile leiten sich deshalb per
  `copyWith` aus `Theme.of(context).textTheme` ab.
- **`ListTile` löst die Farbe seiner Symbole selbst auf** und überstimmt eine
  umgebende `IconTheme`. Die Gruppenfarbe kam erst über
  `ListTileThemeData.iconColor` an. Sie färbt allerdings führende **und**
  folgende Symbole — deshalb tragen die Chevrons ein eigenes, graues Widget
  (`_Chevron`), sonst wäre rechts eine zweite Farbspur entstanden, die nichts
  unterscheidet.

Angesehen über `test/fantasy_einstellungen_vorschau_test.dart` (fester
Bildvergleich, der Schirm zeigt kein Datum). Der Test braucht einen echten
`User` in `currentUserProvider` — ohne ihn greift der Schirm auf
`Supabase.instance` zu, die es im Test nicht gibt, und die ID muss `createdBy`
treffen, sonst fehlen Admin-Bereich und Gefahrenzone.

### Punktevergabe — nach Position, nicht nach Kategorie

Die Wertung stand als eine lange Liste da, nach Kategorien sortiert, mit
hartkodierten Zahlen im Text. Wer wissen wollte, was sein Innenverteidiger für
eine Null hinten bekommt, musste sich das aus „Zu Null: TW/ABW 12, MF/ST 0"
selbst heraussuchen — und für Positionen mitlesen, die ihn nichts angingen.

Jetzt wählt oben ein `PillSelector` die Position (Torwart, Abwehr, Mittelfeld,
Sturm), und darunter steht **nur, was für diese Position gilt**. Drei Regeln
halten das ehrlich:

- **Jede Zahl kommt aus `FantasyScoringRules`**, keine steht als Text im
  Schirm. Die Wertung liegt ohnehin schon doppelt vor (`scoring.config.json` ↔
  `fantasy_scoring_rules.dart`); eine dritte Kopie in Anzeigetexten hätte
  niemand mitgepflegt.
- **Was für die Position 0 ist, fehlt ganz.** Eine Zeile „Zu Null: 0" beim
  Stürmer ist keine Auskunft, sondern eine Falle — sie liest sich, als gäbe es
  die Wertung und sie sei nur gerade wertlos. Beim Torwart stehen dafür Parade
  und gehaltener Elfmeter, beim Stürmer nicht.
- **Der Einleitungssatz nennt keine Zahl und keine Rangfolge.** Beides ging
  schon schief: „Defensivaktionen bringen ab acht einen Bonus" stand über einer
  Tabelle, die dieselbe Acht aus `defensiveMilestones` rechnet (beim Mittelfeld
  wäre es die Zehn gewesen), und „für die Abwehr zählt die Null hinten am
  meisten" ist schlicht falsch — ein Tor bringt jeder Position 16, die Null 12.
  Der Satz ordnet ein, die Tabelle beziffert.

Angesehen über `test/punktevergabe_vorschau_test.dart`, und zwar mit **zwei**
Bildern: Der Schirm lebt genau davon, dass Torwart und Stürmer verschieden
aussehen — ein Bild allein hätte den halben Zweck nicht gezeigt. Der
Bildvergleich ist fest, der Schirm zeigt kein Datum.

### Ein leeres Feld im Draft-Brett heißt nicht „nicht gedraftet"

Symptom: Ein Spieler war gepickt, aber **bei manchen Accounts** blieb die Zelle
im Brett leer. Die Serverdaten waren dabei einwandfrei — kein Pick ohne
Manager, keiner ohne Runde, keine Dublette, jeder Pick zeigte auf eine echte
`players`-Zeile, und die RLS auf `players` ist `true` für alle.

Die Ursache war der **lokale Spielerpool**. `playerPoolProvider` lädt einmal je
App-Sitzung; `sync-squads` spielt aber täglich Zugänge ein, und der Auto-Pick
zieht serverseitig aus der vollen Tabelle. Wer die App vor dem Sync geöffnet
hatte, kannte den Spieler nicht. Genau deshalb traf es nur *manche* Accounts:
Es hing daran, wann wer die App gestartet hat.

Sichtbar wurde daraus nichts, weil das Brett `playerById[pick.playerId]`
nachschlägt und bei `null` dieselbe Zelle zeichnet wie für ein freies Feld —
nur den Pick-Code, sonst nichts. **Ein Zustand „ich weiß es nicht" wurde als
Zustand „da ist nichts" gerendert.** Derselbe Fehler traf den eigenen Kader,
wo `if (p != null)` den Spieler wortlos aus der Aufstellung fallen ließ.

Drei Änderungen:

- **Ein Pick sieht nie aus wie ein freies Feld.** Kennt der Pool den Spieler
  nicht, bekommt die Zelle Fläche und „Wird geladen …" statt Leere.
- **Der Pool lädt nach**, sobald ein Pick auf eine unbekannte ID zeigt
  (`_poolNachladenFallsUnbekannt`, einmal je ID, aus dem Ticker — `ref.invalidate`
  im `build` ist verboten).
- **`picksStream` trägt den vollständigen Primärschlüssel.** Er lautet
  `league_id, phase, pick_number`; der Client meldete nur zwei Spalten. Im
  Dynasty-Modus fängt die Pick-Nummerierung je Phase wieder bei 1 an — der
  Supabase-Stream hätte Pick 1 des Aufbau-Drafts und Pick 1 des U20-Drafts für
  dieselbe Zeile gehalten und die eine mit der anderen überschrieben. Bisher
  unentdeckt, weil noch keine Liga eine zweite Phase erreicht hat.

Die Lehre über den Draft hinaus: **Wo ein Client eine Server-ID gegen einen
gecachten Katalog auflöst, ist „nicht gefunden" ein eigener Zustand.** Ihn auf
denselben Pixel zu rendern wie „leer" macht aus einem Ladeproblem einen
Datenverlust — für den, der draufschaut.

### Die Aufstellung speicherte automatisch — und verlor dabei vier Wege lang

Gemeldet als „die Aufstellungsbearbeitung hat nicht gespeichert". Der Speichern-
Pfad hatte **keinen Knopf**, sondern einen Timer mit 700 ms Verzögerung und
darunter die Zeile *„Änderungen werden automatisch gespeichert"*. Diese Zeile
war der eigentliche Fehler: Sie stand da auch dann, wenn gar nichts gespeichert
werden konnte.

Vier Wege, auf denen eine Änderung wortlos verschwand:

- **`dispose()` verwarf den offenen Speichervorgang.** `_saveTimer?.cancel()`
  und sonst nichts. Wer den letzten Spieler zog und innerhalb der 700 ms
  zurücktippte, verlor die Elf. Jetzt wird eine offene, gültige Änderung im
  `dispose` noch abgeschickt (ohne `await`, der Schirm ist ja weg) — dafür hält
  der State das Repository seit `initState` selbst, weil `ref` dann nicht mehr
  verlässlich ist.
- **Lief schon ein Speichern, fiel die neuere Änderung weg.** Die Bedingung
  `!_saving` brach ab, ohne einen neuen Versuch zu planen. Zwei Züge kurz
  hintereinander — der zweite kam nie an. Jetzt bestellt sich der Versuch neu
  ein.
- **Bei unvollständiger Elf passierte nichts, und niemand sagte es.** Das
  Nichtsenden ist richtig (der Server nähme sie ohnehin nicht), das Schweigen
  nicht: Wer zehn von elf Plätzen füllt und „wird automatisch gespeichert"
  liest, geht beruhigt weg.
- **Der Notnagel `?? 34` schrieb auf den falschen Spieltag.** `round` kam aus
  `current ?? 34`, und der Schirm rendert, sobald der *Pool* geladen ist — auf
  `fantasyCurrentRoundProvider` wartet er nicht. Wer schnell genug zog, sicherte
  seine Elf für **Spieltag 34**: vom Server angenommen, für Spieltag 1
  unsichtbar, ohne Fehlermeldung. In `fantasy_lineups` steht genau so eine
  Zeile (07.07.2026). `_effRound` ist jetzt `int?` und wird nur mit dem echten
  Wert belegt; ohne Spieltag wird gewartet, nicht geraten.

Die Fußzeile kennt jetzt **drei** Zustände statt einem: „Nicht gespeichert – die
Elf ist noch nicht vollständig" (rot), „Speichere …", „Gespeichert".

Gehalten wird das von `test/aufstellung_autospeichern_test.dart`. Die
Entscheidung lag als Bedingung in einem Timer-Rückruf und war damit nicht
prüfbar; sie steht jetzt als reine Funktion in
`logic/lineup_autosave.dart` (`naechsterSpeicherSchritt`). Jeder Testfall dort
war einmal eine Änderung, die verschwand.

**Die Lehre:** Ein Auto-Speicher ohne Knopf nimmt dem Nutzer die Rückmeldung,
die der Knopf gab. Dann muss die Statuszeile *jeden* Zustand sagen können —
besonders „ich habe nichts gespeichert". Eine Zeile, die immer dasselbe
verspricht, ist schlimmer als keine.

### „Man muss die App komplett schließen" war kein Performance-Problem

So wurde es gemeldet, und es klang nach Langsamkeit. Es war das Gegenteil: Die
App fragte gar nicht mehr nach. Drei Schichten, die alle in dieselbe Richtung
versagten — deshalb half nur der harte Neustart.

- **`fantasy_league_members` stand nicht in der Realtime-Publication.** Zehn
  andere Fantasy-Tabellen schon (`fantasy_rosters`, `draft_picks`,
  `fantasy_leagues`, `fantasy_lineups` …) — ausgerechnet die Mitgliederliste
  nicht. Ein Beitritt **konnte** nicht ankommen, egal wie der Client fragte.
  Migration 0082 nimmt sie auf, dazu `tip_rounds` und `tip_round_members`, wo
  „jemand tritt bei" derselbe Vorgang ist.
- **Die beiden wichtigsten Listen waren `FutureProvider`.**
  `myFantasyLeaguesProvider` (die Ligen auf dem Startbildschirm) und
  `fantasyManagersProvider` (die Teilnehmer) luden genau einmal. Ein
  gestarteter Draft und ein neuer Mitspieler kamen deshalb nie an. Beide sind
  jetzt `StreamProvider`.
  Bei den Mitgliedern geht das nur über eine **Klingel**: `managers()` braucht
  den eingebetteten Join auf `profiles` (Name, Avatar), und ein Supabase-
  `.stream()` kann keine Joins. Der Stream meldet deshalb nur, *dass* sich
  etwas geändert hat (`memberChanges`), und `asyncMap` holt die vollständige
  Abfrage nach. Die erste Ausgabe ist der Snapshot, das Erstladen läuft also
  über denselben Weg.
- **Es gab keinen einzigen `AppLifecycleState`-Beobachter.** Nichts wurde beim
  Zurückholen aus dem Hintergrund aufgefrischt — und genau deshalb reichte es
  nicht, die App wegzulegen und wiederzuholen. `MainShell` beobachtet den
  Lebenszyklus jetzt und ruft `beimZurueckkommenAktualisieren`
  (`app/wiedereinstieg.dart`); dort steht als Liste, was neu geholt wird, mit
  dem Grund. Er sitzt in der Hülle, damit es für alle Tabs gilt.
  Auch Streams stehen in der Liste: Eine Realtime-Verbindung überlebt eine
  lange Pause nicht zwangsläufig; sie verbindet sich neu, hat die Ereignisse
  der Auszeit aber nicht gesehen. Ein frischer Schnappschuss ist billiger als
  ein falscher Stand.
  **Nicht in der Liste:** rein Lokales (Favoriten, Lesemarken) und alles, was
  gerade bearbeitet wird — ein Neuladen unter den Händen wäre schlimmer als
  ein Wert von vor zehn Minuten.

**Mit hinausgeflogen ist eine Notlösung**, die das Problem verdeckte und dabei
Last erzeugte: Der Draft-Raum rief alle zwei Sekunden
`ref.invalidate(fantasyManagersProvider)` — der Kommentar dort sagte den Grund
offen („Mitglieder kommen nicht per Realtime"). Das hielt die Liste nur *im
Draft-Raum* aktuell und fragte dafür im Sekundentakt ab.

**Die Regel daraus:** Eine Tabelle, deren Änderungen jemand sehen soll, braucht
**beides** — den Eintrag in `supabase_realtime` und einen Provider, der zuhört.
Fehlt eins von beidem, sieht es wie Trägheit aus. Prüfen lässt es sich in einer
Zeile:

```sql
select tablename from pg_publication_tables where pubname = 'supabase_realtime';
```

### Das Draft-Board bleibt erreichbar

Nach dem letzten Pick verschwand der Draft-Raum aus der Liga-Übersicht
(`if (!draftFullyDone)`), und damit war das Board weg — wer nachsehen wollte,
wer wen gezogen hat, hatte keinen Weg mehr dorthin. In den
Fantasy-Einstellungen steht jetzt unter der Marke **Draft** die Zeile
*Draft-Board*, für **alle** Mitglieder (der Liga-Block darüber ist
`if (isOwner)`; das Board ist keine Verwaltung, sondern Nachschau).

**Nicht der Draft-Raum wird wieder geöffnet, sondern nur das Board.**
`DraftBoardScreen` ist bewusst ein eigener Schirm: Der Raum bringt einen
Sekunden-Ticker, den Auto-Pick-Umschalter, die Wunschliste und den
Verfügbar-Tab mit — nach dem letzten Pick tut davon nichts mehr etwas, aber
der Ticker baut weiter jede Sekunde das ganze Brett neu auf (bei 18 Teams über
250 Zellen, nicht lazy). Das Nachschau-Board steht still.

Zwei Details, die beim Bauen aufkamen:

- **`_BoardTab` heißt jetzt `DraftBoard`** und ist öffentlich — es hat mit dem
  neuen Schirm ein zweites Zuhause. Der Rest des Draft-Raums bleibt privat.
- **Gezeichnet werden nur die Runden, die es gibt** (`max(round)` aus den
  Picks), nicht `roundsThisPhase`. Unter einem abgebrochenen Draft hingen
  sonst leere Zeilen. Und im Dynasty-Modus erscheint ein `PillSelector` für
  die Phase — aber nur, wenn wirklich in mehr als einer gedraftet wurde.

Angesehen über `test/draft_board_vorschau_test.dart` (fester Bildvergleich,
kein Datum im Bild). Die Vorschau baut vier Runden Snake mit vier Teams: Genau
daran sieht man, ob die Umkehr stimmt — R1 läuft 1.01→1.04, R2 zurück
2.01→2.04 auf der anderen Seite.

### Kader-Limits je Position — und warum ein Trigger, keine sechs Funktionen

Anlass aus der laufenden Liga: Ein Manager hatte **acht Stürmer und drei
Abwehrspieler**. Mit der Formationsspanne (ABW 3–5, ST 1–3) blieb ihm genau
eine mögliche Aufstellung, 1-3-4-3; fällt einer der drei Verteidiger aus,
bekommt er *gar keine* gültige Elf mehr zusammen. Fünf Kaderplätze waren tot.

**Zwei Sorten Grenzen, und sie werden leicht verwechselt:**

| | Was sie begrenzen | Wo sie stehen | Seit |
|---|---|---|---|
| `defMin`/`defMax`, `midMin`/… | die **Startelf** (Formation) | `roster`-JSONB | schon immer |
| `maxGk`/`maxDef`/`maxMid`/`maxFwd` | den **Kader** (Besitz) | `roster`-JSONB | 0083 |

- **Fehlt ein `max…`-Schlüssel, gilt kein Limit.** Absicht: Als das entstand,
  liefen zwei Drafts, und eine stillschweigend eingeführte Obergrenze hätte sie
  mitten im Lauf blockiert. Wer Limits will, setzt sie unter *Regeln & Format →
  Kader-Limits*.
- **Bestehende Kader brechen nicht.** Der Trigger prüft nur beim *Hinzufügen*;
  wer schon darüber liegt, behält seine Spieler und kann auf dieser Position
  nur nichts mehr dazunehmen. Die Seite sagt das auch hin („Ein Kader liegt
  schon über einem Limit"). Rückwirkend Spieler wegzunehmen wäre keine Regel,
  sondern eine Enteignung.
- **Geprüft wird am Ende der Transaktion, nicht zwischen zwei Zeilen.** Der
  Trigger lief zuerst als `before insert or update` — und ein **1:1-Tausch
  scheiterte daran**, obwohl er nichts ändert. `fantasy_respond_trade` bewegt
  die Spieler einzeln, als Schleife über `fantasy_trade_items`; zwischen zwei
  Durchläufen hat die empfangende Seite den neuen Spieler schon und den eigenen
  noch, also einen zu viel. Zwei Teilnehmer sind darüber gestolpert.
  Seit 0087 ist es ein `constraint trigger ... deferrable initially deferred`:
  Er läuft beim Commit, wenn alle Bewegungen erledigt sind. Zwei Eigenheiten
  gehören dazu — Constraint-Trigger müssen `after` sein (Rückgabewert wird
  ignoriert), und sie feuern auch für Zeilen, die in derselben Transaktion
  wieder verschwunden sind; deshalb steigt die Funktion aus, wenn es die Zeile
  beim Commit nicht mehr gibt.
  **Die Lehre allgemein:** Eine Mengenregel („höchstens N davon") darf nicht
  auf eine Momentaufnahme mitten in einer mehrschrittigen Operation schauen.
  Wer so eine Regel als Row-Trigger schreibt, muss sie aufschieben — sonst
  verbietet sie Vorgänge, die am Ende völlig regelkonform sind.
- **Ein Trigger auf `fantasy_rosters`, keine sechs Funktionen.** Spieler kommen
  über `fantasy_make_pick`, den Auto-Pick (`fantasy_advance`),
  `fantasy_add_free_agent`, `fantasy_process_waivers`, `fantasy_admin_add` und
  `fantasy_respond_trade` in einen Kader. Sechs Stellen sind sechs
  Gelegenheiten, eine zu vergessen — und der siebte Weg, den jemand nächstes
  Jahr baut, wäre von vornherein außen vor. **Trades laufen über ein `update`
  von `manager_id`**, nicht über Delete+Insert; der Trigger hängt deshalb an
  `insert or update`.
- **Der Auto-Pick musste mit.** Zöge er nach seiner Rangliste einen Stürmer auf
  eine volle Position, würfe der Trigger — und der Draft stünde, exakt der
  Zustand, den 0079 gerade beseitigt hat. Der Filter sitzt deshalb **in der
  Auswahl** (auch in der Wunschliste), nicht als nachträgliche Prüfung.
- **Die Summe der Limits muss die Kadergröße erreichen.** 16 Runden mit Limits,
  die zusammen 12 ergeben, wären nicht streng, sondern kaputt: Der Draft fände
  keinen erlaubten Spieler mehr und beendete sich selbst. Die Seite sperrt das
  Speichern (`limitsReichenFuerKader`, getestet), und eine offene Position
  (`null`) rettet immer.

**Die Limit-Seite hat bewusst ihre eigene Repository-Methode.**
`updateDraftSettings` filtert auf `.eq('draft_status','setup')` — richtig für
Rundenzahl und Pickzeit, falsch hier: Limits regeln auch Free Agency, Waiver
und Trades, also die ganze Saison. `updateRosterLimits` lässt den Filter weg
und hängt ein `select()` an: Ein `update`, das null Zeilen trifft, ist für
PostgREST kein Fehler, und die Oberfläche hätte „Gespeichert" gemeldet — genau
die stille Variante, die die Teilnehmerzahl schon einmal hatte.

**Jede Position steht für sich.** Man kann die Torhüter deckeln und Abwehr,
Mittelfeld und Sturm offen lassen — ein fehlender `max…`-Schlüssel heißt für
Trigger und Auto-Pick „unbegrenzt", und zwar je Position einzeln. Modell und
SQL konnten das von Anfang an; eingeschränkt hatte nur die erste Fassung der
Oberfläche, die einen einzigen Schalter für alle vier hatte.

Drei Dinge, die dabei zu beachten waren:

- **„Ohne Limit" ist ein Knopf, keine Null.** Eine 0 im Stepper hieße *keiner
  erlaubt* — das genaue Gegenteil von *unbegrenzt*.
- **Die Summenprüfung gilt nur, wenn alle vier gesetzt sind.** Bleibt eine
  Position offen, nimmt sie jede Restmenge auf; „zusammen 12 von 16" wäre dann
  eine Warnung vor einem Problem, das es nicht gibt (`_alleGesetzt`).
- **Eigene Zeile statt `_SettingRow`.** Dessen `ListTile` gibt dem `trailing`
  nur begrenzt Platz, und dort stehen bis zu drei Bedienelemente (Stepper plus
  Aufheben-Knopf). Die Breiten kontrolliert `_LimitZeile` selbst.

Angesehen über `test/kaderlimits_vorschau_test.dart` — bewusst der **gemischte**
Fall (Torhüter und Sturm begrenzt, Abwehr und Mittelfeld offen), weil genau
dieser Unterschied auf einen Blick lesbar sein muss. Gerechnet wird in
`test/kaderlimits_test.dart`.

Gegen die Produktions-DB nachgemessen (mit Rollback): Mit nur `maxFwd` gesetzt
wird ein Stürmer blockiert („höchstens 1 Stürmer in dieser Liga") und ein
Abwehrspieler durchgelassen. Nach 0087 ebenso nachgestellt: Ein 1:1-Tausch bei
vollem Limit geht durch, ein echter Zugang auf dieselbe Position nicht.
**Aufgeschobene Trigger prüft man mit `set constraints <name> immediate`** —
sonst feuern sie erst beim Commit, den ein Probelauf mit Rollback nie erreicht.

### Die Aufstellung sperrt je Spieler, nicht je Spieltag

Vorher galt **ein** Riegel für alles: `fantasy_round_deadline` liefert den
frühesten Anpfiff der Runde, und ab dem nahm `fantasy_set_lineup` gar nichts
mehr an. Wer am Freitagabend das Eröffnungsspiel verpasst hatte, konnte auch
seinen Sonntagsspieler nicht mehr tauschen — zwei Tage Sperre für null
Informationsvorsprung.

Seit Migration 0084 zählt der Anpfiff **des jeweiligen Spielers**. Drei Punkte,
die man dabei richtig treffen muss:

- **Geprüft wird nur die Änderung, nicht die Aufstellung.** Jeder Spieler, der
  dazukommt oder herausfällt, muss noch spielfrei sein; wer **drin bleibt**,
  wird nicht geprüft. Sonst wäre nach dem ersten Anpfiff wieder jede
  Speicherung blockiert — die unveränderten Spieler stehen ja weiter in der
  Liste, und wir hätten die alte Sperre zurück, nur umständlicher.
- **Beide Richtungen sperren.** Nicht nur das Hereinnehmen: Wer schon spielt,
  darf auch nicht *heraus*, sonst setzt man den Verteidiger nach seiner Roten
  Karte nachträglich auf die Bank.
- **Kein Spiel gefunden heißt nicht gesperrt.** Der Kader kann Spieler
  enthalten, deren Verein an dem Spieltag nicht spielt oder gar nicht mehr in
  der Liga ist — gemessen: von 19 Vereinen im Pool trifft genau einer keinen
  Spielplan („AS Monaco", ein abgewanderter, noch gerosterter Spieler). Sie zu
  bewegen bringt niemandem einen Vorteil; sie punkten ohnehin nicht.

Die Zuordnung läuft über `players.club` = `fixtures.home_name`/`away_name` —
derselbe kanonische OpenLigaDB-Name, auf dem auch das Stats-Matching steht.
**Nachgemessen: 18 von 19 Vereinen treffen exakt.** `min(kickoff)`, weil
derselbe Spieltag doppelt gespiegelt sein kann (`openligadb:` und
`sportmonks:`) — die Anstoßzeit ist dann dieselbe.

**Der Client muss dieselbe Regel meinen wie der Server**, sonst zeigt die App
ein Feld als bedienbar, das der Server dann ablehnt. Sie steht deshalb als
reine Funktion in `logic/aufstellung_sperre.dart` (`anpfiffJeVerein`,
`spielerGesperrt`) mit Tests, und die Oberfläche zieht daraus:

- Gesperrte Spieler tragen ein **Schloss** am Wappen und „läuft" statt der
  Positions-Pille — sie reagieren nicht mehr stumm nicht, sondern sagen warum.
- Sie lassen sich weder ziehen noch überschreiben, und der Spielerwahl-Dialog
  **bietet sie gar nicht erst an**.
- Die **Formations-Chips** verschwinden, sobald *irgendein* aufgestellter
  Spieler gesperrt ist: Ein Formationswechsel schiebt die ganze Elf durch, das
  ginge nicht teilweise.
- Die Kopfzeile sagt die Zahl („3 Spieler sind gesperrt, ihre Spiele laufen")
  statt pauschal „Aufstellung gesperrt" — das wäre ab dem Freitagsspiel schlicht
  falsch.

### Der MatchUp-Kasten war buchstäblich undurchsichtig

So kam die Meldung, und sie traf es wörtlich. Vier Ursachen, alle im selben
Kasten (`MatchupBanner`/`HeroShell` in `matchup_hero.dart`):

- **Ein Chevron lag als Wasserzeichen mit 45 % Deckung quer über dem Inhalt.**
  Genau so ein „halbtransparenter Dekor-Chevron" ist auf der Liga-Übersicht
  schon einmal geflogen (siehe oben) — hier war er stehen geblieben. Er kostet
  Lesbarkeit an der einzigen Stelle des Schirms, an der eine Zahl zählt.
  Ersatzlos entfernt.
- **Die Akzentfarbe füllte die ganze Fläche**, auch vor dem Anpfiff. Grün heißt
  in dieser App „hier läuft etwas"; ein grüner Kasten für einen Spieltag, der
  erst Samstag beginnt, sagt das Falsche. Jetzt trägt er den Kartengrund und
  nur einen **Hauch aus der Ecke** — kräftig solange live, leiser wenn beendet,
  gar nicht davor. Dasselbe Muster wie bei den Ligakarten (`_kartenFlaeche`).
- **Der Punktestand stand zwischen den Namen** und nahm ihnen die Breite:
  „lennartruepke" schrumpfte auf Winzgröße, aus „FÜHRT" wurde „F…", und bei
  „92 : 78,5" blieb links „SF…" statt SFV03. Er steht jetzt **mittig auf einer
  eigenen Zeile**; jede Seite bekommt die halbe Kastenbreite. Der Name schrumpft
  außerdem statt zu kappen (`FittedBox`), dieselbe Regel wie im Live-Tab.
- **Unter dem Momentum-Balken standen dieselben zwei Zahlen** wie zwei Zeilen
  darüber im Punktestand — dieselbe Auskunft dreimal in einem Kasten, der
  ohnehin zu voll war. Nur die Beschriftung ist geblieben.

**Der Überlauf, den erst die Vorschau zeigte:** `RenderFlex overflowed by 14
pixels` in der „FÜHRT"/„SIEG"-Zeile — auf dem Gerät der schwarz-gelbe Balken.
Beide Beschriftungen sitzen jetzt in `Flexible`. Ohne
`test/matchup_banner_vorschau_test.dart` wäre der nie aufgefallen: Auf dem Gerät
sieht man immer nur den einen Zustand, den die eigene Liga gerade hat, und der
Überlauf trat nur bei langem Namen **und** angepfiffenem Spieltag auf.

**Und dann kam der Überlauf zurück, den ich selbst gebaut hatte:** Die neue
Punktestand-Zeile macht den Kasten höher, und im MatchUp-Tab steckt er in einem
`PageView` **fester** Höhe — dort stand eine nackte `224`, und das Gerät zeigte
4 px Überlauf nach unten. Eine Zahl, die dem Inhalt hinterherlaufen muss, gehört
nicht an zwei Stellen: Sie steht jetzt als `kMatchupBannerHoehe` beim Banner,
das Karussell liest sie, und die Vorschau rendert einen Kasten **genau in dieser
Höhe** mit den längsten Namen und vierstelligen Punktzahlen. Wächst der Inhalt
wieder darüber hinaus, wird der Test rot statt das Gerät.

Die Vorschau zeigt deshalb fünf Fälle untereinander (vor dem Spieltag, live,
beendet, in Karussell-Höhe, spielfrei). `MatchupBanner` bekommt seine Daten
explizit — der Provider-Teil steckt in `MatchupHero` —, deshalb braucht sie
keinen einzigen Provider.

**Beim Prüfen selbst danebengegriffen, zweimal:** Ein `grep` auf
`^flutter: .*overflowed` findet Flutters Fehlerblöcke **nicht** — die stehen
ohne `flutter:`-Präfix im Log, und die Meldung „keine Ausgabe = sauber" war
schlicht falsch. Und `tail -n "+$(wc -l < datei)"` scheitert an den führenden
Leerzeichen von `wc`. Wer im Log nach Layoutfehlern sucht: auf `overflowed`
suchen, ohne Präfix, und den Bereich ab der letzten Zeile `Restarted
application` nehmen — sonst zählt man Fehler aus dem Code von vor dem Neustart.

### Mehr Aufstellungen: von acht auf neun — und warum es nicht elf wurden

Die Spannen standen im FPL-Zuschnitt (ABW 3–5, MF 2–5, ST 1–3) und ließen genau
**acht** Formationen zu. Geweitet auf MF 6 und ST 4 (Migration 0085) waren es
elf — neu: 3-3-4, 4-2-4, 3-6-1. Zwei davon sind auf ausdrücklichen Wunsch
wieder weg (0086), 4-2-4 ist geblieben. Stand: **neun**.

**Dabei kam die Grenze des Modells zum Vorschein.** 3-6-1 ließ sich sauber über
die Spanne entfernen — `midMax` zurück auf 5, es ist die einzige Formation mit
sechs Mittelfeldspielern. 3-3-4 nicht: Es braucht dasselbe `fwdMax` 4 wie
4-2-4 und unterscheidet sich nur in der Abwehr. **Reine Min/Max-Spannen können
das eine nicht ohne das andere entfernen.** Dafür gibt es jetzt eine Regel, die
zwei Positionen zugleich anschaut:

> Vier Stürmer nur mit mindestens vier Abwehrspielern.

`RosterConfig.vierStuermerBrauchenVierAbwehr` — und **dieselbe Regel ein zweites
Mal in SQL** (`fantasy_set_lineup`), bewusste Doppelung wie bei
`tip_scoring.dart` ↔ SQL-View. Laufen die beiden auseinander, bietet die App
eine Formation an, die der Server ablehnt.

**Zur Migration:** Alle bestehenden Ligen tragen die Spannen ausgeschrieben in
`fantasy_leagues.roster` (`RosterConfig.toJson` schreibt sie immer) — ein
geänderter Default in Dart bewirkt dort nichts. 0085 weitete mit `greatest`
(nur nach oben), 0086 nimmt `midMax` mit `least` zurück. **Verengen ist die
heikle Richtung**, deshalb vorher nachgemessen: keine einzige gespeicherte
Aufstellung nutzte sechs Mittelfeldspieler oder vier Stürmer bei drei
Abwehrspielern.

Zwei Dinge, die dabei mit hochkamen:

- **Die Formationsleiste benutzte `ChoiceChip`** — genau das Material-Element,
  das diese Datei verbietet (stumpfes Oliv aus `secondaryContainer`). Jetzt
  `PillChip`.
- **Ein bestehender Test hing an der alten Grenze**, ohne es zu sagen:
  `weekly_recap_test` baute „vier treffende Stürmer, einer muss auf die Bank" —
  mit `fwdMax` 4 starten alle vier. Das Szenario ist um einen Stürmer verschoben
  und benennt die Abhängigkeit jetzt im Kommentar.

Gehalten wird der Stand von `test/formationen_test.dart`: vollständige Liste,
die Kopplungsregel einzeln, und die Zusicherung, dass gegenüber dem
FPL-Zuschnitt **nichts wegfällt**.

### „Kader voll" nach einem 1:1-Tausch — und ein doppelter Lemke

Zwei Meldungen, eine Ursache, und sie lag **nicht** dort, wo sie klang.

Gemeldet als „Kaderlimit ist voll, obwohl ich 1 zu 1 getauscht habe" — der
Verdacht fiel sofort auf den Kader-Limit-Trigger aus 0083. Nachgemessen: **In
keiner Liga ist überhaupt ein Positionslimit gesetzt** (alle `max…`-Schlüssel
`null`), der Trigger kann also gar nicht feuern. Die Meldung stammt von
`myPlayers.length >= league.roster.squadSize` in `player_action_buttons.dart`,
also von einer **clientseitigen** Zählung.

Und die zählte falsch, weil `rosterStream` Dubletten durchließ. `.stream()`
führt einen ersten Schnappschuss und die laufenden Realtime-Ereignisse
zusammen; dabei kann dieselbe Zeile kurzzeitig zweimal in der Liste stehen. Aus
16 Kaderplätzen wurden scheinbar 17 → „Kader voll". Und im Aufstellungs-Editor
landete derselbe Spieler beim Formationswechsel auf **zwei Plätzen** (gemeldet
als „hat Lemke dupliziert") — die Elf hatte damit nur zehn verschiedene Spieler
und ließ sich nicht mehr speichern.

**Der Quirk war im Projekt längst bekannt**: `DraftRepository.queueStream`
entdoppelt seit jeher von Hand und sagt im Kommentar auch warum. Nur stand das
an genau einer Stelle. Jetzt gibt es `ohneDubletten`
(`core/data/stream_dubletten.dart`), und alle Streams mit dem einfachen Muster
laufen hindurch — Kader, Aufstellungen, Trades, Beitrittsanfragen, Chat, Ligen
und Draft-Picks.

**Die Lehre:** Ein `.stream()` liefert **keine** garantiert dublettenfreie
Liste. Wer aus so einer Liste eine **Anzahl** ableitet (Kadergröße, „voll?",
Zähler) oder sie **positionsweise verteilt**, muss vorher entdoppeln. Wer sie
nur anzeigt, merkt es nie — deshalb fiel es erst auf, als daran eine Regel hing.

Nicht angefasst sind die Streams mit eigenem Rechenweg (`leagueStream` nimmt
ohnehin `rows.first`, `waiverPlayersStream` baut ein `Set`) — dort richtet eine
Dublette nichts an.

### Trade: derselbe Spieler sieht überall gleich aus

Gemeldet: „Die Trade-Angebot-Boxen sind nur Schrift." Stimmte — die
Angebotskarte listete die Spieler als Komma-Satz („J. Urbig, S. Kolo Muani").
Dieselbe Auskunft wie eine Spielerkarte, aber ohne Verein, ohne Position und
ohne Wiedererkennung. Wer ein Angebot beurteilen soll, schaut auf Spieler,
nicht auf einen Satz.

Die reiche Karte gab es längst — als private `_tile` in der Auswahlspalte des
Trade-Screens: Positionsfarbe als Fläche, das Wappen groß und halb über den
rechten Rand hinaus, Name und Position links. Sie ist jetzt
`SpielerKachel` (`ui/spieler_kachel.dart`) und steht an **allen drei** Stellen
des Trade-Wegs:

| Schirm | vorher | jetzt |
|---|---|---|
| Auswahl | die Karte (110 px) | dieselbe Karte |
| Bestätigung vor dem Senden | Pillen mit Namen | dieselbe Karte, 58 px |
| Angebotskarte | Komma-Satz | dieselbe Karte, 58 px |

**Kompakt heißt auch schmal.** Der erste Wurf zog die Kacheln über die volle
Kartenbreite — für Name und Position wirkte das viel zu groß, und drei Spieler
machten die Angebotskarte doppelt so hoch wie nötig. Jetzt haben sie eine feste
Breite (152 × 46) und laufen in einem `Wrap` nebeneinander. Damit skaliert auch
der Platz, den das überstehende Wappen rechts wegnimmt, mit der Kartenhöhe
statt fest bei 60 px zu stehen — sonst bliebe auf einer schmalen Karte für den
Namen fast nichts übrig.

Drei Parameter tragen den Unterschied: `hervor` (kräftige Positionsfarbe statt
gedämpfter Fläche), `breite` und `mitHaken`. In der Auswahl heißt kräftig „ausgewählt"
und bekommt ein Häkchen; im Angebot heißt es schlicht „das ist der Inhalt" —
ein Haken wäre dort eine Behauptung über eine Entscheidung, die niemand
getroffen hat. Wappengröße und Schriftgrad folgen der Kartenhöhe, sonst sähe
die kompakte Fassung aus wie die große mit abgeschnittenem Rand.

**Ein unbekannter Spieler verschwindet nicht.** Kennt der lokale Pool die ID
nicht (Zugang aus `sync-squads` nach dem App-Start), steht sie kursiv da statt
ausgelassen zu werden — dieselbe Regel wie beim Draft-Brett: „nicht gefunden"
ist ein eigener Zustand, nicht dasselbe wie „nichts dabei". Die Vorschau
`test/trade_angebot_vorschau_test.dart` enthält genau diesen Fall, dazu ein
eingehendes Angebot (mit Annehmen/Ablehnen) neben einem selbst gestellten —
auf dem Gerät sieht man immer nur eins von beiden.

## Liga-Übersicht — „C, das Duell führt"

Fünfter Schirm nach demselben Verfahren (`design/liga-uebersicht/`).
**Besonderheit:** Dieser Screen sieht in drei Phasen verschieden aus — Aufbau,
Draft, Saison. Richtung C beschreibt nur die Saison; für die beiden anderen
Phasen ist Richtung A umgesetzt, sonst hätte der Schirm in zwei von drei
Zuständen keinen Kopf.

- **Der Draft startet nur nach Rückfrage**, und zwar auf jedem Weg. Die
  Bestätigung samt Start liegt in `ui/draft_start.dart`
  (`draftStartenMitBestaetigung`) — der Knopf im Draft-Raum und der im
  Auftrags-Kopf rufen dieselbe Stelle. Der Kopf-Knopf **öffnete vorher nur den
  Raum**, obwohl er „Draft starten" hieß: ein Knopf, der ankündigt zu starten
  und stattdessen navigiert. Nach dem Start führt er in den Raum, weil dort ab
  jetzt die Uhr läuft.
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
  **Die Leiste nimmt die volle Breite ein**, jeder Reiter denselben Anteil.
  Vorher standen die Wörter links zusammengedrängt in einer waagerecht
  scrollbaren Zeile, und rechts blieb Leere — die Leiste sah aus wie ein
  angefangener Satz. Damit ist auch das Scrollen weg: Passt ein Wort nicht,
  schrumpft es (`FittedBox`), wie überall sonst.
  **Der MatchUp-Reiter trägt das Markenzeichen statt des Wortes** — aktiv in
  den Markenfarben (grün|rot), ruhend einfarbig mitgedämpft wie die
  Nachbarwörter; sonst riefe das Logo als einziges Element dauerhaft laut. Die
  Zeile hat dafür eine **feste Höhe**, damit ein Zeichen die Marke nicht gegen
  die Wörter der Nachbarreiter verschiebt. Der Text aus `titel` bleibt
  trotzdem stehen: als Beschriftung für die Vorlesehilfe — ein Logo ohne Namen
  ist für VoiceOver eine stumme Schaltfläche.
  **Die erste Fassung war dafür zu leise** und hatte einen Platzierungsfehler:
  ein 2 px breiter Rahmenstrich über die volle Wortbreite, hart auf der
  Unterkante der Leiste — und weil sie im `AppBar.bottom` sitzt, begann direkt
  darunter die erste Karte. Der Strich sah aus, als gehöre er zu ihr
  („klebt an der MatchUp-Box"). Jetzt: eine **kurze gerundete Marke** statt
  eines Unterstrichs, sie **wächst hinein** statt umzuspringen, und darunter
  liegen Luft und eine Haarlinie über die volle Breite — dieselbe Trennung wie
  bei den Kapitelmarken. Die Höhe ist von 44 auf 52 gegangen.
  **Falle dabei, dieselbe wie in den Fantasy-Einstellungen:**
  `AnimatedDefaultTextStyle` *ersetzt* den Stil, es ergänzt ihn nicht. Ein
  blankes `TextStyle` verliert damit die `fontFamily` — in der Vorschau wurden
  die Reiter zu leeren Kästchen, auf dem Gerät wäre es stumm Roboto statt
  Barlow Condensed gewesen. Der Stil leitet sich deshalb per `copyWith` aus
  `Theme.of(context).textTheme` ab. Ohne
  `test/leise_reiter_vorschau_test.dart` wäre das durchgegangen; die Vorschau
  zeigt beide Einbauorte (vier Wörter im `AppBar.bottom`, zwei mitten im
  Schirm) und **unter jeder Leiste eine angedeutete Karte** — ohne die ließe
  sich der Abstand, um den es ging, gar nicht beurteilen.
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
