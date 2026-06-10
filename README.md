# Tippspiel & Fantasy App

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
- ⬜ Push-Benachrichtigungen, Profil-Verwaltung
- ⬜ Fantasy-Modus (Draft, Roster, Live-Scoring)

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
