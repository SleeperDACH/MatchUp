#!/usr/bin/env python3
"""Letzte-Saison-Statistiken (Bundesliga 2025/26) je Spieler aus Sportmonks.

Erzeugt supabase/migrations/0059_player_season_totals_2025.sql: rohe
Saison-Aggregate (Tore, Assists, Minuten, Karten, Zu-Null, Einsätze) je
Pool-Spieler. Damit lässt sich clientseitig mit dem jeweiligen Liga-Scoring
eine Draft-Reihenfolge „bester zuerst" berechnen.

Matching ist trivial und exakt: die Pool-Spieler tragen bereits
Sportmonks-IDs (id = 'sportmonks:<pid>'), daher wird direkt über die
Sportmonks-player_id abgeglichen (kein Namensraten).

Abruf effizient über die 18 Kader der Saison 25646 (nested statistics),
statt ~500 Einzelabrufe.

Aufruf:
    python3 tools/import_last_season_stats.py
(SPORTMONKS_API_KEY, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY aus
 supabase/.env.local werden automatisch gelesen.)
"""
import json
import os
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_SQL = os.path.join(ROOT, "supabase/migrations/0059_player_season_totals_2025.sql")
ENV = os.path.join(ROOT, "supabase/.env.local")

BASE = "https://api.sportmonks.com/v3/football"

# Bundesliga 2025/26 (letzte abgeschlossene Saison). Startjahr 2025 = App-Saison.
SM_SEASON = 25646
APP_SEASON = 2025

# Sportmonks-Statistik-Typ-IDs (per API verifiziert).
T_GOALS, T_ASSISTS, T_YELLOW, T_RED = 52, 79, 84, 83
T_MINUTES, T_CLEANSHEETS, T_APPEARANCES = 119, 194, 321


def env_val(key):
    v = os.environ.get(key)
    if v:
        return v.strip()
    with open(ENV) as f:
        for line in f:
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip()
    raise SystemExit(f"{key} nicht gefunden.")


TOKEN = env_val("SPORTMONKS_API_KEY")
SB_URL = env_val("SUPABASE_URL")
SB_KEY = env_val("SUPABASE_PUBLISHABLE_KEY")


def _get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.load(r)
        except Exception:
            if attempt == 3:
                raise
            time.sleep(0.8 * (attempt + 1))


def sm(path):
    sep = "&" if "?" in path else "?"
    return _get(f"{BASE}{path}{sep}api_token={TOKEN}",
                {"Accept": "application/json",
                 "User-Agent": "Mozilla/5.0"})


def pool_ids():
    """Sportmonks-player_id -> Pool-player_id ('sportmonks:<pid>')."""
    out = {}
    url = (f"{SB_URL}/rest/v1/players?select=id&id=like.sportmonks:*"
           "&limit=2000")
    data = _get(url, {"apikey": SB_KEY, "Authorization": f"Bearer {SB_KEY}"})
    for row in data:
        pid = row["id"].split(":", 1)[1]
        out[pid] = row["id"]
    return out


def totals_from_details(details):
    m = {}
    for d in details:
        v = d.get("value") or {}
        m[d.get("type_id")] = v.get("total", 0) if isinstance(v, dict) else 0
    return {
        "goals": int(m.get(T_GOALS, 0) or 0),
        "assists": int(m.get(T_ASSISTS, 0) or 0),
        "minutes": int(m.get(T_MINUTES, 0) or 0),
        "yellow": int(m.get(T_YELLOW, 0) or 0),
        "red": int(m.get(T_RED, 0) or 0),
        "clean_sheets": int(m.get(T_CLEANSHEETS, 0) or 0),
        "appearances": int(m.get(T_APPEARANCES, 0) or 0),
    }


def main():
    pool = pool_ids()
    print(f"Pool-Spieler mit Sportmonks-ID: {len(pool)}")

    # 18 Teams der Saison 25646.
    teams = sm(f"/seasons/{SM_SEASON}?include=teams")["data"].get("teams", [])
    print(f"Teams der Saison {SM_SEASON}: {len(teams)}")

    stats = {}  # sm_pid -> totals
    for t in teams:
        tid, tname = t["id"], t.get("name", "?")
        d = sm(f"/squads/seasons/{SM_SEASON}/teams/{tid}"
               f"?include=player.statistics.details"
               f"&filters=playerStatisticSeasons:{SM_SEASON}")
        members = d.get("data", []) or []
        hit = 0
        for e in members:
            p = e.get("player") or {}
            pid = str(p.get("id"))
            for s in (p.get("statistics") or []):
                if s.get("season_id") != SM_SEASON:
                    continue
                tot = totals_from_details(s.get("details", []))
                if tot["appearances"] > 0 or tot["minutes"] > 0:
                    stats[pid] = tot
                    hit += 1
                break
        print(f"  {tname:28s} team={tid:>6}  Kader={len(members):>3}  mit Stats={hit}")
        time.sleep(0.2)

    # Auf Pool-Spieler abbilden.
    matched = {pool[pid]: tot for pid, tot in stats.items() if pid in pool}
    print(f"\nSportmonks-Spieler mit Stats: {len(stats)}")
    print(f"Davon im Pool (gerankt): {len(matched)}")
    print(f"Pool-Spieler ohne Last-Season-BL-Stats: {len(pool) - len(matched)}")

    rows = sorted(matched.items())
    values = ",\n".join(
        f"('{pid}', {APP_SEASON}, {t['goals']}, {t['assists']}, {t['minutes']}, "
        f"{t['yellow']}, {t['red']}, {t['clean_sheets']}, {t['appearances']})"
        for pid, t in rows
    )

    sql = f"""-- Rohe Saison-Aggregate der letzten Bundesliga-Saison (2025/26) je
-- Pool-Spieler, aus Sportmonks (Typ-IDs: Tore 52, Assists 79, Minuten 119,
-- Gelb 84, Rot 83, Zu-Null 194, Einsätze 321). Generiert von
-- tools/import_last_season_stats.py.
--
-- Zweck: clientseitig mit dem jeweiligen Liga-Scoring eine Draft-Reihenfolge
-- „bester zuerst" berechnen. season = Startjahr (2025 = 2025/26).

create table if not exists public.player_season_totals (
  season       int  not null,
  player_id    text not null references public.players (id) on delete cascade,
  goals        int  not null default 0,
  assists      int  not null default 0,
  minutes      int  not null default 0,
  yellow       int  not null default 0,
  red          int  not null default 0,
  clean_sheets int  not null default 0,
  appearances  int  not null default 0,
  primary key (season, player_id)
);

alter table public.player_season_totals enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'player_season_totals'
      and policyname = 'Saison-Totals sind öffentlich lesbar'
  ) then
    create policy "Saison-Totals sind öffentlich lesbar"
      on public.player_season_totals for select using (true);
  end if;
end $$;

delete from public.player_season_totals where season = {APP_SEASON};

insert into public.player_season_totals
  (player_id, season, goals, assists, minutes, yellow, red, clean_sheets, appearances)
values
{values};
"""

    with open(OUT_SQL, "w") as f:
        f.write(sql)
    print(f"\nGeschrieben: {OUT_SQL} ({len(rows)} Zeilen)")


if __name__ == "__main__":
    main()
