# Tippspiel & Fantasy App

**Live-Demo:** https://sleeperdach.github.io/meine_app/

Neu deployen: `flutter build web --base-href "/meine_app/" --dart-define=…`
(Keys aus `supabase/.env.local`), dann den Inhalt von `build/web`
auf den Branch `gh-pages` pushen.

Fantasy-Sport-App nach dem Vorbild von Sleeper, kombiniert mit einem
Tippspiel-Modus à la Kicktipp. Start: Bundesliga-Tippspiel (MVP).
Geplante Ausbaustufen: Fantasy-Modus, Top-5-Ligen Europas, NFL, NBA.

## Status (Phase 1: Tippspiel-MVP)

- ✅ Sport-agnostisches Domainmodell (Sport → Liga → Saison → Runde → Spiel)
- ✅ OpenLigaDB-Anbindung (kostenlos): Bundesliga + WM 2026
- ✅ Wettbewerbs-Auswahl pro Liga (beim Erstellen); K.o.-Runden bei
  Turnieren navigierbar, sobald OpenLigaDB sie kennt
- ✅ Homescreen: Liga auswählen / erstellen / beitreten; Tippabgabe,
  Rangliste und eigene Punkte erst innerhalb der Liga
- ✅ Länderflaggen bzw. Vereinslogos vor den Teamnamen (flutter_svg)
- ✅ Spieltag-Ansicht mit Tipp-Eingabe, Sperre ab Anstoß, Live-/Endstände
- ✅ Scoring-Engine (Kicktipp-Standard: exakt 4 / Differenz 3 / Tendenz 2, konfigurierbar)
- ✅ Punkteübersicht über die Saison
- ✅ Supabase-Schema für Tipprunden mit Freunden (`supabase/migrations/`)
- ✅ Supabase-Projekt `tippspiel` (eu-central-1) inkl. Fixture-Sync:
  Edge Function `sync-fixtures` spiegelt OpenLigaDB alle 10 Min per
  pg_cron in die `fixtures`-Tabelle (Zugangsdaten: `supabase/.env.local`,
  nicht im Git)
- ✅ Supabase-Anbindung im Client: Registrierung/Login, Tipprunden
  erstellen & per Einladungscode beitreten, Tipps serverseitig
  (Deadline per RLS), Rangliste pro Runde
- ✅ Fantasy-Modus (Hauptfokus): Liga/Dynasty-Modi, Liga-Erstellung,
  Manager-Beitritt per Code, Spielerpool (Bundesliga) mit
  Alter/U20/Auslands-Flag. **Snake-Draft-Raum** mit einstellbarer Pickzeit
  (30 Sek–1 Tag, Live + Slow), Auto-Pick und Realtime — server-autoritativ.
  **Scoring** (Kickbase-Stil, konfigurierbar) aus echten OpenLigaDB-Daten
  (Tore + Zu-Null); „Mein Team" + Liga-Tabelle mit bester Startelf.
  **Dynasty**: U20-Sperre im Haupt-Draft + separater U20-Draft
  (U20-Spieler & Auslands-Neuzugänge) für die neue Saison.
  **Free Agency**: mutierbarer Kader, Drop & Aufnahme mit Kadergrößen-Limit,
  05.09.-Sperre, U20-Draft erst nach Saisonende.
  **Waiver-Wire**: gedroppte Spieler sind bis zur Deadline (2 Tage vor dem
  Spieltag) nur per Antrag holbar; Abarbeitung läuft terminiert per pg_cron
  in rollender Waiver-Priorität (Start = umgekehrte Draft-Reihenfolge als
  Näherung an die umgekehrte Tabelle, Gewinner rutscht ans Ende). Eigener
  Anträge-Screen mit Rang & Stornierung.
  **Manuelle Aufstellung**: Startelf je Spieltag selbst wählen (feste
  Formation aus der Kader-Konfiguration), serverseitige Deadline zum ersten
  Anstoß; ohne Wahl zählt automatisch die beste Elf. „Mein Team" & Tabelle
  werten die effektive Aufstellung.
  **Stats-Feed**: anbieter-neutrale Tabelle `player_match_stats` als Quelle
  der Wahrheit, serverseitig befüllt (Edge Function `sync-stats` spiegelt
  Tore/Zu-Null aus OpenLigaDB); Schema & Scoring sind bereits auf Assists,
  Karten und Minuten vorbereitet. Client liest die Tabelle, fällt für noch
  nicht gespiegelte Spieltage auf die Live-Berechnung zurück.
- ⬜ Reicherer Stats-Feed anbinden (Assists/Karten/Minuten/Aufstellungen —
  z. B. api-sports), füllt dieselben Spalten ohne Client-Umbau
- ⬜ Waiver-Priorität aus echter umgekehrter Saisontabelle (sobald
  serverseitige kumulierte Punkte existieren)
- ⬜ Flexible Formationen, Saison-Rollover (Dynasty)
- ⬜ Push-Benachrichtigungen, Profil-Verwaltung

## Entwicklung

```sh
flutter pub get
flutter run                 # lokaler Modus, Tipps nur auf dem Gerät
flutter test
```

Mit Supabase-Anbindung (Keys liegen in `supabase/.env.local`):

```sh
./run_dev.sh              # optional z. B. -d macos anhängen
```

Das Datenbankschema liegt in `supabase/migrations/0001_init.sql`
(per Supabase CLI `supabase db push` oder im SQL-Editor einspielen).

## Architektur

Siehe `CLAUDE.md` für die Architektur-Leitlinien (Adapter-Pattern für
Datenquellen, konfigurierbares Scoring, Erweiterung auf neue Ligen).
