#!/usr/bin/env python3
"""Spielerpool-Importer: vollständige Bundesliga-Kader aus Sportmonks.

Erzeugt supabase/migrations/0048_sportmonks_pool.sql: entfernt die alten
seed:/tsdb:-Bundesliga-Einträge (soweit NICHT in bestehenden Ligen
referenziert → FK-sicher) und spielt die kompletten aktuellen Kader der 18
Bundesliga-Vereine ein (Upsert).

Wichtig fürs Scoring: club ist 1:1 der kanonische OpenLigaDB-Name, damit das
Stats-Matching (sync-stats) weiter greift. Deshalb treiben wir den Import über
die 18 kanonischen Vereine + fest aufgelöste Sportmonks-Team-IDs (die
Sportmonks-Saison-Teamliste ist für die kommende Saison unzuverlässig).

Aufruf:
    SPORTMONKS_API_KEY=... python3 tools/import_sportmonks_pool.py
oder Token aus supabase/.env.local (wird automatisch gelesen).
"""
import json
import os
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_SQL = os.path.join(ROOT, "supabase/migrations/0048_sportmonks_pool.sql")
ENV = os.path.join(ROOT, "supabase/.env.local")

BASE = "https://api.sportmonks.com/v3/football"

# Kanonischer OpenLigaDB-Vereinsname -> Sportmonks-Team-ID (Herren-1.-Mannschaft).
TEAM_IDS = {
    "1. FC Heidenheim 1846": 2831,
    "1. FC Köln": 3320,
    "1. FC Union Berlin": 1079,
    "1. FSV Mainz 05": 794,
    "Bayer 04 Leverkusen": 3321,
    "Borussia Dortmund": 68,
    "Borussia Mönchengladbach": 683,
    "Eintracht Frankfurt": 366,
    "FC Augsburg": 90,
    "FC Bayern München": 503,
    "FC St. Pauli": 353,
    "Hamburger SV": 2708,
    "RB Leipzig": 277,
    "SC Freiburg": 3543,
    "SV Werder Bremen": 82,
    "TSG Hoffenheim": 2726,
    "VfB Stuttgart": 3319,
    "VfL Wolfsburg": 510,
}

# Sportmonks position.developer_name -> App-Position.
POS = {
    "GOALKEEPER": "gk",
    "DEFENDER": "def",
    "MIDFIELDER": "mid",
    "ATTACKER": "fwd",
    "FORWARD": "fwd",
}

# FK-Referenzen auf players (für das sichere Löschen).
FK_REFS = [
    ("draft_picks", "player_id"),
    ("fantasy_draft_queue", "player_id"),
    ("fantasy_rosters", "player_id"),
    ("fantasy_trade_items", "player_id"),
    ("fantasy_waiver_claims", "add_player_id"),
    ("fantasy_waiver_claims", "drop_player_id"),
    ("fantasy_waiver_players", "player_id"),
    ("player_match_stats", "player_id"),
]


def token():
    t = os.environ.get("SPORTMONKS_API_KEY")
    if t:
        return t.strip()
    with open(ENV) as f:
        for line in f:
            if line.startswith("SPORTMONKS_API_KEY="):
                return line.split("=", 1)[1].strip()
    raise SystemExit("SPORTMONKS_API_KEY nicht gefunden.")


TOKEN = token()


def api(path):
    url = f"{BASE}{path}"
    req = urllib.request.Request(url, headers={
        "Authorization": TOKEN,
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                      "AppleWebKit/537.36",
        "Accept": "application/json",
    })
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(0.6 * (attempt + 1))


def sql_str(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    players = {}  # id -> row-tuple
    skipped = 0
    for club, team_id in sorted(TEAM_IDS.items()):
        d = api(f"/squads/teams/{team_id}?include=player.position;player.nationality")
        entries = d.get("data", [])
        kept = 0
        for e in entries:
            p = e.get("player") or {}
            pid = p.get("id")
            name = (p.get("display_name") or p.get("name") or "").strip()
            dob = p.get("date_of_birth")
            posobj = p.get("position") or {}
            pos = POS.get((posobj.get("developer_name") or "").upper())
            natobj = p.get("nationality") or {}
            nat = (natobj.get("iso2") if isinstance(natobj, dict) else None)
            nat = nat.lower() if nat else None
            if not (pid and name and dob and pos and nat):
                skipped += 1
                continue
            players[pid] = (
                f"sportmonks:{pid}", name, pos, club, dob, nat)
            kept += 1
        print(f"  {club:30s} team={team_id:>6}  Kader={len(entries):>3}  übernommen={kept}")
        time.sleep(0.15)

    clubs_sql = ", ".join(sql_str(c) for c in sorted(TEAM_IDS))
    # NOT IN über alle FK-Spalten (Nulls ausschließen!).
    ref_union = "\n    union ".join(
        f"select {col} from public.{tbl} where {col} is not null"
        for tbl, col in FK_REFS
    )

    rows = sorted(players.values(), key=lambda r: (r[3], r[1]))
    values = ",\n".join(
        f"({sql_str(r[0])}, {sql_str(r[1])}, '{r[2]}', {sql_str(r[3])}, "
        f"'{r[4]}', '{r[5]}', false)"
        for r in rows
    )

    sql = f"""-- Vollständiger Bundesliga-Spielerpool aus Sportmonks (aktuelle Kader).
-- Generiert von tools/import_sportmonks_pool.py. club = kanonischer
-- OpenLigaDB-Name (fürs Stats-Matching). Ersetzt die alten Bundesliga-
-- Einträge, soweit sie nicht in bestehenden Ligen referenziert sind.

-- 1) Alte, NICHT referenzierte Bundesliga-Spieler entfernen (FK-sicher).
delete from public.players p
where p.club in ({clubs_sql})
  and p.id not in (
    {ref_union}
  );

-- 2) Aktuelle Sportmonks-Kader einspielen ({len(rows)} Spieler, Upsert).
insert into public.players
  (id, name, position, club, birth_date, nationality, is_foreign_newcomer)
values
{values}
on conflict (id) do update set
  name = excluded.name,
  position = excluded.position,
  club = excluded.club,
  birth_date = excluded.birth_date,
  nationality = excluded.nationality;
"""
    with open(OUT_SQL, "w") as f:
        f.write(sql)

    print(f"\n→ {len(rows)} Spieler, {skipped} übersprungen (ohne Pos/DOB/Nat).")
    print(f"→ Migration geschrieben: {OUT_SQL}")


if __name__ == "__main__":
    main()
