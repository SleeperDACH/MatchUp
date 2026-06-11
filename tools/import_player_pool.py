#!/usr/bin/env python3
"""Spielerpool-Importer: aktuelle Bundesliga-Kader aus TheSportsDB.

Erzeugt supabase/migrations/0010_player_pool_expand.sql aus dem kostenlosen
TheSportsDB-Feed (Key '3'). Der Gratis-Key liefert je Verein bis zu 10
aktuelle Spieler (lookup_all_players); zusammen mit dem kuratierten Seed aus
0004 ergibt das einen deutlich groesseren Pool.

Wichtig fuers Scoring: club ist 1:1 der kanonische OpenLigaDB-Name (Saison
2025), damit das Stats-Matching (Tore per Torschuetzen-Nachname, Zu-Null per
Verein) in RoundScoringService / sync-stats weiter greift. Spieler, die schon
im 0004-Seed stehen (gleicher normalisierter Name + Verein), werden
uebersprungen, damit niemand doppelt draftbar ist.

Aufruf (kein API-Key noetig):
    python3 tools/import_player_pool.py
"""
import json
import os
import re
import time
import unicodedata
import urllib.request

API = "https://www.thesportsdb.com/api/v1/json/3"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED_SQL = os.path.join(ROOT, "supabase/migrations/0004_fantasy_draft.sql")
OUT_SQL = os.path.join(ROOT, "supabase/migrations/0010_player_pool_expand.sql")

# Kanonischer OpenLigaDB-Vereinsname -> TheSportsDB-Team-ID (Saison 2025/26).
# Aufgeloest ueber searchteams.php; Maenner-Erstvertretung. Die "2. Liga"-Tags
# bei einzelnen Teams sind veraltete TheSportsDB-Metadaten, die ID stimmt.
TEAM_IDS = {
    "1. FC Heidenheim 1846": "134696",
    "1. FC Köln": "133654",
    "1. FC Union Berlin": "134690",
    "1. FSV Mainz 05": "133665",
    "Bayer 04 Leverkusen": "133666",
    "Borussia Dortmund": "133650",
    "Borussia Mönchengladbach": "134779",
    "Eintracht Frankfurt": "133814",
    "FC Augsburg": "133652",
    "FC Bayern München": "133664",
    "FC St. Pauli": "133813",
    "Hamburger SV": "133651",
    "RB Leipzig": "134695",
    "SC Freiburg": "133653",
    "SV Werder Bremen": "133662",
    "TSG Hoffenheim": "133657",
    "VfB Stuttgart": "133660",
    "VfL Wolfsburg": "133655",
}

# Land (TheSportsDB strNationality) -> ISO-Code fuer flagcdn. Unbekannt -> 'un'.
NAT = {
    "Germany": "de", "England": "gb-eng", "Scotland": "gb-sct", "Wales": "gb-wls",
    "Northern Ireland": "gb-nir", "France": "fr", "Spain": "es", "Portugal": "pt",
    "Italy": "it", "Netherlands": "nl", "Belgium": "be", "Switzerland": "ch",
    "Austria": "at", "Croatia": "hr", "Serbia": "rs", "Slovenia": "si",
    "Slovakia": "sk", "Czech Republic": "cz", "Czechia": "cz", "Poland": "pl",
    "Denmark": "dk", "Sweden": "se", "Norway": "no", "Finland": "fi",
    "Iceland": "is", "Ireland": "ie", "Republic of Ireland": "ie", "Turkey": "tr",
    "Greece": "gr", "Hungary": "hu", "Romania": "ro", "Bulgaria": "bg",
    "Ukraine": "ua", "Russia": "ru", "USA": "us", "United States": "us",
    "Canada": "ca", "Mexico": "mx", "Brazil": "br", "Argentina": "ar",
    "Uruguay": "uy", "Colombia": "co", "Chile": "cl", "Ecuador": "ec",
    "Paraguay": "py", "Peru": "pe", "Venezuela": "ve", "Japan": "jp",
    "South Korea": "kr", "Korea Republic": "kr", "Australia": "au",
    "Nigeria": "ng", "Ghana": "gh", "Senegal": "sn", "Ivory Coast": "ci",
    "Cote d'Ivoire": "ci", "Cameroon": "cm", "Morocco": "ma", "Algeria": "dz",
    "Tunisia": "tn", "Egypt": "eg", "Mali": "ml", "Guinea": "gn",
    "Burkina Faso": "bf", "DR Congo": "cd", "Congo DR": "cd", "Gabon": "ga",
    "Israel": "il", "Georgia": "ge", "Armenia": "am", "Albania": "al",
    "Kosovo": "xk", "North Macedonia": "mk", "Bosnia and Herzegovina": "ba",
    "Montenegro": "me", "Luxembourg": "lu", "Zambia": "zm", "South Africa": "za",
    "Jamaica": "jm", "Iran": "ir", "New Zealand": "nz", "Angola": "ao",
    "Cape Verde": "cv", "Togo": "tg", "Benin": "bj", "Madagascar": "mg",
    "Comoros": "km", "Guinea-Bissau": "gw", "Estonia": "ee", "Latvia": "lv",
    "Lithuania": "lt", "Gambia": "gm", "Suriname": "sr", "Libya": "ly",
}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "meine_app/1.0"})
    return json.load(urllib.request.urlopen(req, timeout=25))


def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", s).strip()


def position(s):
    s = (s or "").lower()
    if "goalkeeper" in s or "keeper" in s:
        return "gk"
    if "midfield" in s:  # "Defensive Midfield" zaehlt als Mittelfeld
        return "mid"
    if "winger" in s or "forward" in s or "striker" in s or "attack" in s:
        return "fwd"
    if "back" in s or "defen" in s:
        return "def"
    return "mid"


def seed_keys():
    """(normalisierter Name, Verein) aller Spieler aus dem 0004-Seed."""
    txt = open(SEED_SQL, encoding="utf-8").read()
    rows = re.findall(r"\('seed:[^']*','((?:[^']|'')*)','\w+','((?:[^']|'')*)'", txt)
    return {(norm(n.replace("''", "'")), c.replace("''", "'")) for n, c in rows}


def esc(s):
    return s.replace("'", "''")


def main():
    skip = seed_keys()
    print(f"Seed-Spieler: {len(skip)}")
    rows, seen = [], set()
    for club, tid in TEAM_IDS.items():
        data = get(f"{API}/lookup_all_players.php?id={tid}")
        added = 0
        for p in data.get("player") or []:
            pid, name = p.get("idPlayer"), (p.get("strPlayer") or "").strip()
            if not pid or not name or pid in seen:
                continue
            if (norm(name), club) in skip:
                continue
            seen.add(pid)
            dob = (p.get("dateBorn") or "")[:10]
            if not re.match(r"\d{4}-\d{2}-\d{2}", dob):
                dob = "1900-01-01"
            rows.append((
                f"tsdb:{pid}", name, position(p.get("strPosition")), club, dob,
                NAT.get((p.get("strNationality") or "").strip(), "un"),
            ))
            added += 1
        print(f"  {club:28s} +{added}")
        time.sleep(0.4)

    rows.sort(key=lambda r: (r[3], r[1]))
    values = ",\n".join(
        f"  ('{esc(i)}','{esc(n)}','{pos}','{esc(c)}','{d}','{nat}',false)"
        for i, n, pos, c, d, nat in rows
    )
    header = (
        "-- Spielerpool-Erweiterung: aktuelle Bundesliga-Kader aus TheSportsDB\n"
        "-- (kostenloser Feed, Key '3'). Der Gratis-Key liefert je Verein bis zu\n"
        "-- 10 aktuelle Spieler; zusammen mit dem kuratierten Seed aus 0004 ergibt\n"
        f"-- das einen deutlich groesseren Pool ({len(rows)} neue Spieler).\n"
        "--\n"
        "-- Vereinsnamen sind 1:1 die kanonischen OpenLigaDB-Namen (Saison 2025),\n"
        "-- damit das Stats-Matching (Tore per Torschuetzen-Nachname, Zu-Null per\n"
        "-- Verein) in RoundScoringService / sync-stats weiter greift.\n"
        "-- Geburtsdaten sind taggenau (besser als der jahresgenaue Seed).\n"
        "-- is_foreign_newcomer bleibt false (fuer die Dynasty-U20-Logik tragen die\n"
        "-- kuratierten Seed-Talente die korrekten Flags; neue Spieler default false).\n"
        "--\n"
        "-- ids sind 'tsdb:<idPlayer>'. ON CONFLICT macht die Migration idempotent.\n"
        "-- Generiert per tools/import_player_pool.py — nicht von Hand pflegen.\n\n"
        "insert into public.players\n"
        "  (id, name, position, club, birth_date, nationality, is_foreign_newcomer)\n"
        "values\n"
    )
    open(OUT_SQL, "w", encoding="utf-8").write(header + values + "\non conflict (id) do nothing;\n")
    print(f"Geschrieben: {OUT_SQL} ({len(rows)} Spieler)")


if __name__ == "__main__":
    main()
