# Push-Benachrichtigungen in MatchUp — Stand und Anleitung

> Dieselben Inhalte gibt es als **`PUSH.pdf`** — gesetzt, mit Seitenumbrüchen
> je Schritt — und als **`PUSH-OFFEN.pdf`**, dem Auszug mit nur den offenen
> Punkten. Beide werden aus `docs/push.html` bzw. `docs/push_offen.html`
> gebaut:
>
> ```sh
> tools/push_pdf.sh
> ```
>
> **Wer den Stand ändert, ändert beide Seiten** — diese Datei und die
> zugehörige HTML. Die erste Fassung der PDFs entstand aus Dateien außerhalb
> des Repos; sie ließen sich danach nicht mehr erzeugen und zeigten tagelang
> einen Schritt als offen, der längst erledigt war.

Stand: 21.09.2026. Diese Datei sagt, **was schon da ist**, **was fehlt** und
**wie du das Fehlende besorgst** — Schritt für Schritt, ohne Vorwissen.

Alles mit ❌ musst du selbst machen (es hängt an deinen Konten). Alles mit 🔧
mache ich, sobald das Nötige da ist.

---

## Erledigt am 21.09.2026 (Nachmittag)

| Sache | Wert |
|-------|------|
| Firebase-Projekt | **MatchUp**, Projekt-ID `matchup-f9e83`, Projektnummer `325263487271` |
| Google-Konto | valentinsohrmann@gmail.com, Spark-Tarif (kostenlos) |
| Google Analytics | **nicht** aktiviert |
| Android-App | `app.matchup.mobile`, Alias *MatchUp Android*, App-ID `1:325263487271:android:dfb76d44a31e292ac33902` |
| Apple-App | `app.matchup.mobile`, Alias *MatchUp iOS*, App-ID `1:325263487271:ios:51b677fbdec52c4ec33902` |
| Datenschutzerklärung | neuer **Abschnitt 6 „Push-Benachrichtigungen"**, Abschnitte 6–13 auf 7–14 gerückt — **seit 25.09.2026 veröffentlicht** unter `sleeperdach.github.io/datenschutz.html`, Quelle `docs/datenschutz.html` |

**Steht seitdem ebenfalls** (24.09.2026):

| Sache | Wo |
|-------|-----|
| APNs-Schlüssel | `~/keys/AuthKey_9JF35BFS9Q.p8`, Key ID `9JF35BFS9Q` |
| Firebase-Konfigdateien | `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` (letztere auch im Xcode-Projekt eingetragen) |
| Dienstkonto | `~/keys/firebase-dienstkonto.json` (nicht im Repo, `.gitignore` greift) |
| Datenbank | Migration `0129_push_benachrichtigungen.sql` — Geräte, Einstellungen, Ausgangskorb, neun Auslöser, zwei Cron-Jobs |
| Versand | Edge Function `supabase/functions/push` (FCM HTTP v1) |
| App | `firebase_core`/`firebase_messaging`, Berechtigung, Token-Registrierung, Antippen öffnet den Schirm, Einstellungsschirm im Profil |
| Tests | `test/push_ziel_test.dart`, `test/push_einstellungen_test.dart` |

**Was noch bei dir liegt:** Schritt 1 und 2 — Apple-Mitgliedschaft im Team und
das Push-Häkchen für die App-ID — sowie die beiden Store-Angaben.
**Die Datenschutzseite ist seit dem 25.09.2026 veröffentlicht**, und **der
APNs-Schlüssel liegt seit dem 02.10.2026 bei Firebase** (auf deine Auskunft;
die Konsole gibt den Status über keine Schnittstelle heraus, siehe Schritt 6).

**Die Inbetriebnahme unten ist erledigt** (24.09.2026): Migration eingespielt,
Secret gesetzt, Function ausgespielt, drei Cron-Jobs aktiv. Der Server wartet
nur noch auf Geräte.

---

## Die Übersicht

| # | Teil | Status | Wer |
|---|------|--------|-----|
| 1 | Bezahlte Apple-Mitgliedschaft im Team `HACJC6623Z` auf diesem Mac | ❌ fehlt | du |
| 2 | Push-Berechtigung für die App-ID `app.matchup.mobile` | ❌ ungeprüft | du |
| 3 | Key ID des APNs-Schlüssels | ✅ `9JF35BFS9Q` (neu erzeugt) | — |
| 4 | Schlüsseldatei `AuthKey_9JF35BFS9Q.p8` | ✅ in `~/keys/` | — |
| 5 | Team ID | ✅ `HACJC6623Z` | — |
| 6 | Bundle ID | ✅ `app.matchup.mobile` | — |
| 7 | Firebase-Projekt | ✅ `matchup-f9e83`, Analytics aus | — |
| 8 | `GoogleService-Info.plist` (iOS) + `google-services.json` (Android) | ✅ im Projekt | — |
| 9 | Dienstkonto-Schlüssel (JSON) für den Versand | ✅ `~/keys/firebase-dienstkonto.json` | — |
| 10 | **APNs-Schlüssel bei Firebase hinterlegt** | ✅ seit 02.10.2026 (deine Auskunft) | du |
| 11 | Datenschutzerklärung veröffentlicht · Store-Angaben | 🟡 Seite seit 25.09.2026 live, Stores offen | du |
| 12 | `aps-environment` + Hintergrundmodus in der App | ✅ fertig | 🔧 |
| 13 | Push-Paket, Berechtigungsabfrage, Geräte-Tokens | ✅ fertig | 🔧 |
| 14 | Tabelle für Tokens + Einstellungen je Nutzer | ✅ Migration 0129 | 🔧 |
| 15 | Edge Function zum Versenden | ✅ `supabase/functions/push` | 🔧 |

**Geprüft am 21.09.2026:** `security find-identity` kennt nur ein *Apple
Development*-Zertifikat, kein Distribution-Zertifikat. In
`ios/Runner/Runner.entitlements` steht nur Sign in with Apple. Im Projekt gibt
es keine Firebase-Dateien, und `pubspec.yaml` nennt Firebase kein einziges Mal.

---

## Wichtig, bevor du anfängst

- Die **Key ID** (`9JF35BFS9Q`) ist keine Geheimnummer, die darfst du
  weitergeben.
- Die **Datei `.p8` ist das Geheimnis.** Ihren Inhalt nirgends hineinkopieren —
  auch nicht in einen Chat. Wenn ich sie brauche, sag mir den **Dateipfad**.
- Die `.p8` gehört **nicht** ins Git-Repository. In `.gitignore` stehen dafür
  jetzt `*.p8` und `*firebase-adminsdk*.json` — die beiden echten Geheimnisse.
  **`google-services.json` und `GoogleService-Info.plist` stehen bewusst nicht
  darin:** Sie sind keine Geheimnisse (sie liegen in jedem ausgelieferten
  Build) und müssen mit ins Repo, sonst baut das Projekt auf einem zweiten
  Rechner nicht.
- **Android geht ohne Apple.** Wenn Punkt 1 dauert, fangen wir mit Android an
  (nur Punkt 7, 8, 9) und schalten iOS später dazu. Der Server-Teil ist
  derselbe.

---

## Schritt 1 — Apple-Mitgliedschaft auf diesem Mac einrichten ❌

**Warum:** Ohne bezahltes Team darf die App keine Push-Benachrichtigungen
verwenden. Ein persönliches Team reicht nicht. Das ist derselbe Grund, aus dem
`flutter build ipa` scheitert.

1. Xcode öffnen.
2. Menü **Xcode → Settings…** (oder `⌘` + `,`).
3. Reiter **Accounts**.
4. Unten links auf **+** → **Apple ID** → **Continue**.
5. Mit der Apple ID anmelden, die zum bezahlten Team **HACJC6623Z** gehört.
6. Nach der Anmeldung links das Konto anklicken. Rechts muss **MatchUp**
   (Team-ID `HACJC6623Z`) in der Liste stehen, Rolle *Account Holder*, *Admin*
   oder *App Manager*.
7. Rechts unten **Download Manual Profiles** klicken.

**Fertig, wenn** im Terminal dieser Befehl eine Zeile mit *Apple Distribution*
zeigt:

```sh
security find-identity -v -p codesigning
```

Steht dort weiterhin nur *Apple Development*, bist du im falschen Team
angemeldet oder die Mitgliedschaft ist abgelaufen.

---

## Schritt 2 — Push für die App-ID einschalten ❌

**Warum:** Apple muss wissen, dass genau diese App Push benutzen darf.

1. <https://developer.apple.com/account> öffnen, anmelden.
2. Oben rechts prüfen: Steht dort das Team **MatchUp / HACJC6623Z**? Wenn nicht,
   über das Auswahlfeld wechseln.
3. Links **Certificates, Identifiers & Profiles** → **Identifiers**.
4. In der Liste **app.matchup.mobile** anklicken.
5. Häkchen bei **Push Notifications** setzen.
6. Oben rechts **Save**, die Rückfrage mit **Confirm** bestätigen.

**Fertig, wenn** neben *Push Notifications* ein Häkchen steht und die Seite
*Enabled* anzeigt.

---

## Schritt 3 — Die Schlüsseldatei `.p8` besorgen ✅

**Erledigt am 24.09.2026.** Die Datei liegt als `~/keys/AuthKey_9JF35BFS9Q.p8`.
Die Anleitung bleibt stehen, falls der Schlüssel je ersetzt werden muss.

**Warum:** Sie ist der eigentliche Schlüssel. Key ID und Team ID sind nur die
Kennnummern dazu.

**Erst suchen.** Die Datei heißt `AuthKey_9JF35BFS9Q.p8`. Im Finder `⌘` + `⇧` +
`F`, dann `AuthKey` eingeben und auf **„Diesen Mac"** stellen. Oder im
Terminal:

```sh
find ~ -name "AuthKey_*.p8" 2>/dev/null
```

**Wenn sie auftaucht:** an einen sicheren Ort legen (nicht ins Projekt), z. B.
`~/keys/`. Fertig, weiter bei Schritt 4.

**Wenn nicht — neuen Schlüssel anlegen.** Apple gibt eine `.p8` nur **einmal**
heraus; ein verlorener Schlüssel lässt sich nicht erneut laden.

1. <https://developer.apple.com/account> → **Certificates, Identifiers &
   Profiles** → links **Keys**.
2. Den alten Schlüssel `9JF35BFS9Q` anklicken → **Revoke** → bestätigen.
   (Er ist ohne Datei nutzlos. Keine Sorge: Es benutzt ihn noch nichts.)
3. Oben auf **+** (Create a key).
4. **Key Name**: `MatchUp Push`.
5. Häkchen bei **Apple Push Notifications service (APNs)**.
6. **Continue** → **Register**.
7. **Download** klicken. Die Datei landet in `~/Downloads`.
8. **Die neue Key ID notieren** — sie steht auf der Seite und im Dateinamen
   (`AuthKey_XXXXXXXXXX.p8`). Sag sie mir, dann trage ich sie hier ein.
9. Datei verschieben:

```sh
mkdir -p ~/keys && mv ~/Downloads/AuthKey_*.p8 ~/keys/
```

**Fertig, wenn** `ls ~/keys/AuthKey_*.p8` die Datei anzeigt.

---

## Schritt 4 — Firebase-Projekt anlegen ✅

**Erledigt am 21.09.2026.** Projekt `matchup-f9e83`, Spark-Tarif, Analytics aus.

**Warum:** Firebase Cloud Messaging verschickt die Nachrichten an iOS **und**
Android über einen Weg. Ohne Firebase müsste ich zwei Versandwege bauen.

Kostet nichts (Spark-Tarif reicht).

1. <https://console.firebase.google.com> öffnen, mit einem Google-Konto
   anmelden.
2. **Projekt hinzufügen**.
3. Name: `MatchUp`. **Weiter**.
4. Google Analytics: **ausschalten** (brauchen wir nicht, spart eine
   Datenschutz-Baustelle). **Projekt erstellen**.
5. Warten, bis es fertig ist, dann **Weiter**.

**Fertig, wenn** du die Projektübersicht siehst.

---

## Schritt 5 — Die beiden Apps in Firebase eintragen ✅

**Erledigt am 21.09.2026.** Beide Konfigdateien liegen im Projekt
(`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`).

### Android

1. In der Projektübersicht auf das **Android-Symbol**.
2. **Android-Paketname**: `app.matchup.mobile` — genau so, ohne Leerzeichen.
3. Spitzname: `MatchUp Android`. SHA-1 leer lassen.
4. **App registrieren**.
5. **google-services.json herunterladen**.
6. Datei ablegen:

```sh
mv ~/Downloads/google-services.json ~/Projekte/MatchUp/android/app/
```

7. Die nächsten Schritte („Firebase SDK hinzufügen") **überspringen** — das
   mache ich. Unten auf **Weiter** und **Weiter zur Konsole**.

### iOS

1. In der Projektübersicht auf **App hinzufügen** → **iOS**.
2. **Apple-Bundle-ID**: `app.matchup.mobile`.
3. Spitzname: `MatchUp iOS`. App Store ID leer lassen.
4. **App registrieren**.
5. **GoogleService-Info.plist herunterladen**.
6. Datei ablegen:

```sh
mv ~/Downloads/GoogleService-Info.plist ~/Projekte/MatchUp/ios/Runner/
```

7. Restliche Schritte überspringen, **Weiter zur Konsole**.

**Fertig, wenn** beide Befehle eine Datei zeigen:

```sh
ls ~/Projekte/MatchUp/android/app/google-services.json
ls ~/Projekte/MatchUp/ios/Runner/GoogleService-Info.plist
```

---

## Schritt 6 — Den APNs-Schlüssel bei Firebase hinterlegen ✅

**Erledigt** (02.10.2026, auf deine Auskunft).

**Warum er hier als einziger ohne Messung abgehakt ist:** Die Firebase-Konsole
gibt den Status eines APNs-Schlüssels über keine Schnittstelle heraus, und ein
Sendeversuch hilft auch nicht weiter — FCM weist einen erfundenen Token mit
`INVALID_ARGUMENT` ab, **bevor** es APNs überhaupt befragt. Nachgemessen am
02.10.2026; zu unterscheiden ist der Fall also erst mit einem echten Token.
Ob der Schlüssel wirklich greift, zeigt deshalb erst Schritt 8.

**Warum überhaupt:** Firebase spricht in deinem Namen mit Apple. Dafür braucht
es die `.p8` samt Kennnummern. Die Anleitung bleibt stehen, falls der
Schlüssel je ersetzt wird.

1. Firebase-Konsole → Zahnrad oben links → **Projekteinstellungen**.
2. Reiter **Cloud Messaging**.
3. Abschnitt **Apple-App-Konfiguration** → bei `app.matchup.mobile`:
   **APNs-Authentifizierungsschlüssel** → **Hochladen**.
4. **Datei auswählen**: die `.p8` aus `~/keys/`.
5. **Key ID**: `9JF35BFS9Q` (oder die neue aus Schritt 3).
6. **Team ID**: `HACJC6623Z`.
7. **Hochladen**.

**Fertig, wenn** der Schlüssel mit seiner Key ID in der Liste steht.

---

## Schritt 7 — Dienstkonto-Schlüssel für den Versand ✅

**Erledigt.** Die Datei liegt als `~/keys/firebase-dienstkonto.json` und steht
seit dem 24.09.2026 als Supabase-Secret `FIREBASE_DIENSTKONTO` — im Klartext
ist sie nirgends aufgetaucht.

**Warum:** Unser Server (die Edge Function) muss sich bei Firebase ausweisen,
um Nachrichten zu verschicken.

1. Firebase-Konsole → **Projekteinstellungen** → Reiter **Dienstkonten**.
2. **Neuen privaten Schlüssel generieren** → **Schlüssel generieren**.
3. Die JSON-Datei landet in `~/Downloads`.
4. Ablegen:

```sh
mv ~/Downloads/matchup-*-firebase-adminsdk-*.json ~/keys/firebase-dienstkonto.json
```

**Das ist ein Vollzugriff-Schlüssel.** Nicht weitergeben, nicht ins Repo. Sag
mir nur den Pfad, dann lege ich ihn als Supabase-Secret ab.

**Fertig, wenn** `ls ~/keys/firebase-dienstkonto.json` die Datei zeigt.

---

## Schritt 8 — Datenschutz 🟡

**Die Seite ist veröffentlicht** (25.09.2026):
`sleeperdach.github.io/datenschutz.html` zeigt Abschnitt 6
„Push-Benachrichtigungen", die Quelle liegt als `docs/datenschutz.html` im
Projekt. Beim Übernehmen wurde der `<!DOCTYPE html>` ergänzt — die eingereichte
Fassung begann direkt mit `<html>`, was Browser in den Quirks-Modus schickt; am
Wortlaut wurde nichts geändert.

**Offen bleiben die beiden Store-Angaben** — nur über deine Konten erreichbar.

**Warum:** Firebase ist ein Google-Dienst und verarbeitet eine Geräte-Kennung.
Das muss in der App und in beiden Stores stehen.

- Datenschutzerklärung im Impressum ergänzen: Firebase Cloud Messaging (Google
  Ireland Ltd.), Zweck: Push-Benachrichtigungen, Daten: Geräte-Token.
- App Store Connect → **App-Datenschutz**: „Kennungen → Geräte-ID" angeben.
- Google Play Console → **Datensicherheit**: dasselbe.

Sag Bescheid, wenn du dabei Formulierungen brauchst.

---

## Was ich gemacht habe ✅

Alles davon steht (Stand 24.09.2026):

- **App:** `firebase_messaging` einbinden, Berechtigung abfragen (iOS beim
  ersten Start, Android ab Version 13), `aps-environment` und den
  Hintergrundmodus in die iOS-Einstellungen, Antippen einer Nachricht öffnet
  den passenden Schirm.
- **Datenbank:** Tabelle für Geräte-Tokens je Nutzer mit RLS, dazu
  Einstellungen je Kategorie; ungültige Tokens räumt der Versand selbst weg.
- **Edge Function `push`:** verschickt über Firebase, ausgelöst von
  DB-Triggern bzw. den bestehenden Crons.
- **Einstellungsschirm** mit einem Schalter je Kategorie.
- **Tests** für Token-Speicherung und Auslöser.

**Zum Ausprobieren brauchst du ein echtes iPhone.** Im Simulator ist Push mit
Firebase unzuverlässig; Android geht auch im Emulator.

---

## Was Push auslösen soll (Vorschlag)

Die Ereignisse gibt es alle schon als Realtime-Tabellen:

| Ereignis | Quelle |
|---|---|
| Du bist im Draft am Zug | `draft_picks` |
| Neues Trade-Angebot, angenommen, abgelehnt | `fantasy_trades` |
| Waiver durchgegangen oder nicht | `fantasy_waiver_claims` |
| Direktnachricht, Liga- oder Tipprunden-Chat | `direct_messages`, `*_messages` |
| Aufgestellter Spieler fällt aus | `player_absences` |
| Tipps offen, kurz vor Deadline | `tip_rounds` |
| Beitritts- oder Freundschaftsanfrage | `*_join_requests`, `friendships` |

Sag mir, womit die erste Fassung anfangen soll.

---

## Store-Angaben zum Datenschutz (Schritt 8)

Beide Stores fragen dasselbe ab: Push erhebt genau **eine** Datenart, die
Geräte-Kennung (Push-Token). Kein Tracking, keine Werbung.

### App Store Connect → App-Datenschutz

| Frage | Antwort |
|-------|---------|
| Erfasst die App Daten? | Ja (war schon vorher so) |
| Zusätzlicher Datentyp durch Push | **Identifikatoren → Geräte-ID** |
| Verwendungszweck | **App-Funktionalität** |
| Mit der Identität des Nutzers verknüpft? | **Ja** — der Token hängt am Konto |
| Wird für Tracking verwendet? | **Nein** |

### Google Play Console → Datensicherheit

| Frage | Antwort |
|-------|---------|
| Zusätzlicher Datentyp | **Geräte- oder andere IDs → Geräte- oder andere IDs** |
| Erhoben? | **Ja** |
| Geteilt? | **Nein** (Google ist Auftragsverarbeiter, keine Weitergabe an Dritte) |
| Zweck | **App-Funktionalität** |
| Pflicht oder optional? | **Optional** — Nutzer kann Push ablehnen |
| Bei Übertragung verschlüsselt? | **Ja** |
| Löschung auf Anfrage möglich? | **Ja** |

### Datenschutzerklärung

Der neue **Abschnitt 6 „Push-Benachrichtigungen"** nennt Google Ireland Ltd.
als Dienst (FCM), Apple Distribution International Ltd. als Zustellweg auf
iOS, den Push-Token als Datum, Art. 6 Abs. 1 lit. a DSGVO als Grundlage und
den Widerruf über System- bzw. App-Einstellungen. Die Quelle liegt als
`docs/datenschutz.html` im Projekt und ist **am 25.09.2026 1:1 nach
`sleeperdach.github.io/datenschutz.html` übernommen worden** (Repo
`SleeperDACH/sleeperdach.github.io`, Commit `568350f`). Das Impressum blieb
unverändert; die App verlinkt die Datenschutzseite bereits über
`AppConfig.privacyUrl`, dort war nichts nachzuziehen.


---

## Inbetriebnahme — erledigt am 24.09.2026 ✅

Die Regel aus CLAUDE.md gilt hier genauso: **Eine Function ist erst fertig,
wenn sie ausgespielt und eingeplant ist.** Der Code im Repo beweist nichts —
deshalb steht hier, was nachgemessen ist, nicht was gelaufen sein sollte:

| Was | Nachgemessen |
|-----|--------------|
| Migration 0129 | `push_geraete`, `push_einstellungen`, `push_auftraege` stehen |
| Secret | `FIREBASE_DIENSTKONTO` wird von `supabase secrets list` geführt |
| Function | ausgespielt mit `--no-verify-jwt`, antwortet `{"auftraege":0,"gesendet":0}` |
| Cron | `push-versand` (jede Minute), `push-tipp-erinnerungen` (alle 15 Min), `push-korb-aufraeumen` (04:17) — alle drei `active` |
| Auslöser | 10 Trigger hängen an Chats, Trades, Waivern, Ausfällen, Anfragen |
| Gateway | der Minutenlauf steht mit `200` in `net._http_response` — kein 401 |

**Was noch fehlt, ist kein Server-Teil:** Solange kein Gerät einen Token
gemeldet hat, bleibt der Korb leer und `gesendet` steht auf 0. Dafür braucht es
Schritt 1, 2 und 6 — und ein echtes iPhone.

Die Befehle bleiben hier stehen, falls es je neu aufgesetzt werden muss:

```sh
# 1) Abhängigkeiten und iOS-Pods
flutter pub get
cd ios && pod install && cd ..

# 2) Prüfen
flutter analyze
flutter test

# 3) Datenbank
supabase db push                     # Migration 0129

# 4) Dienstkonto als Secret (Inhalt taucht nirgends im Klartext auf)
supabase secrets set FIREBASE_DIENSTKONTO="$(cat ~/keys/firebase-dienstkonto.json)"

# 5) Function ausspielen — **mit** --no-verify-jwt (siehe 0125)
supabase functions deploy push --no-verify-jwt

# 6) Nachsehen, was wirklich draußen und getaktet ist
supabase functions list
psql "$DB_URL" -c "select jobname, schedule, active from cron.job where jobname like 'push%';"
```

**Gegenprobe von Hand** (schickt nur, was im Korb liegt):

```sh
curl -sS -X POST "https://zleuiewcydrazogkfafp.supabase.co/functions/v1/push" \
  -H "x-sync-secret: <SECRET aus dem Vault>" -H "Content-Type: application/json" -d '{}'
# erwartet: {"auftraege":0,"gesendet":0} bei leerem Korb
```

**Zum Ausprobieren braucht es ein echtes iPhone** — im Simulator ist Push mit
Firebase unzuverlässig. Android geht auch im Emulator. Der schnellste Test:
zwei Konten, eine Direktnachricht. In `push_auftraege` muss binnen Sekunden
eine Zeile stehen, binnen einer Minute mit `gesendet_at`.

**Wenn nichts ankommt**, in dieser Reihenfolge nachsehen:

1. `select count(*) from push_geraete;` — hat das Gerät sich überhaupt gemeldet?
2. `select * from push_auftraege order by id desc limit 5;` — legt der Trigger an?
3. `fehler`-Spalte derselben Zeilen — antwortet FCM mit einem Fehler?
4. `select * from net._http_response order by id desc limit 5;` — kommt der Cron
   am Gateway vorbei? (401 heißt: Deploy ohne `--no-verify-jwt` **und** ohne
   Authorization-Header — siehe 0125.)
