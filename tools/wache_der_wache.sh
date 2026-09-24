#!/usr/bin/env bash
# Wache der Wache: fragt das Lebenszeichen der Sync-Wache ab und schickt einen
# Push, wenn es fehlt. Läuft außerhalb von Supabase (GitHub Actions,
# `.github/workflows/wache-der-wache.yml`), weil ein Wächter in derselben
# Datenbank mit ihr zusammen ausfiele. Hintergrund: Migration 0128.
#
# Lokal:  NTFY_TOPIC=… SUPABASE_URL=… SUPABASE_KEY=… tools/wache_der_wache.sh
#
# Exit 0 = Wache lebt. Exit 1 = Störung (gemeldet oder schon gemeldet) — der
# rote Lauf in GitHub ist der zweite Kanal: GitHub mailt fehlgeschlagene
# geplante Läufe.
set -uo pipefail

: "${NTFY_TOPIC:?NTFY_TOPIC fehlt}"
: "${SUPABASE_URL:?SUPABASE_URL fehlt}"
: "${SUPABASE_KEY:?SUPABASE_KEY fehlt}"
# Die Wache läuft alle 10 Minuten; 30 Minuten sind zwei verpasste Läufe plus
# Spielraum für einen verspäteten GitHub-Zeitplan.
GRENZE="${GRENZE_SEKUNDEN:-1800}"
# Ein anhaltender Ausfall ist ein Vorfall, nicht einer je halbe Stunde.
WIEDERHOLEN_NACH="${WIEDERHOLEN_NACH:-3h}"
TITEL="${TITEL:-MatchUp: Wache der Wache}"

antwort=$(curl -sS --max-time 30 -w $'\n%{http_code}' \
  -X POST "$SUPABASE_URL/rest/v1/rpc/wache_lebenszeichen" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H 'Content-Type: application/json' \
  -d '{}' 2>/dev/null) || antwort=$'\n000'
code=$(tail -n1 <<<"$antwort")
body=$(sed '$d' <<<"$antwort")
alter=$(jq -r '.wache_vor_sekunden // empty' <<<"$body" 2>/dev/null || true)

if [[ "$code" == 200 && "$alter" =~ ^[0-9]+$ && "$alter" -le "$GRENZE" ]]; then
  echo "ok: Sync-Wache zuletzt vor ${alter} s durchgelaufen"
  exit 0
fi

if [[ "$code" != 200 ]]; then
  grund="Datenbank-API nicht erreichbar (HTTP $code). Die Sync-Wache kann so nichts melden."
elif [[ ! "$alter" =~ ^[0-9]+$ ]]; then
  grund="Lebenszeichen ohne Zeitangabe: ${body:0:150}"
else
  grund="Die Sync-Wache ist seit $((alter / 60)) Minuten nicht mehr durchgelaufen (Cron gestoppt oder pruefe_sync bricht ab)."
fi
echo "STOERUNG: $grund"

# **ntfy selbst ist das Gedächtnis.** Der Workflow hat keinen Zustand zwischen
# zwei Läufen; das Topic hebt gesendete Nachrichten zwölf Stunden auf.
if curl -sS --max-time 20 "https://ntfy.sh/$NTFY_TOPIC/json?poll=1&since=$WIEDERHOLEN_NACH" 2>/dev/null |
  jq -e --arg t "$TITEL" 'select(.event == "message" and (.title // "") == $t)' >/dev/null 2>&1; then
  echo "In den letzten $WIEDERHOLEN_NACH schon gemeldet — kein weiterer Push."
  exit 1
fi

jq -n --arg topic "$NTFY_TOPIC" --arg title "$TITEL" \
  --arg message "$grund Nächste Erinnerung frühestens in $WIEDERHOLEN_NACH." \
  '{topic: $topic, title: $title, message: $message, priority: 5}' |
  curl -sS --max-time 20 -H 'Content-Type: application/json' -d @- https://ntfy.sh/ >/dev/null &&
  echo "Push gesendet."
exit 1
