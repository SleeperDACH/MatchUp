#!/usr/bin/env bash
# **Läuft jede Sync-Function noch ohne JWT?**
#
# Der Cron ruft sie über `net.http_post` mit dem Header `x-sync-secret` auf und
# schickt **keinen** Authorization-Header. Wird eine Function ohne
# `--no-verify-jwt` ausgespielt, lehnt das Gateway jeden Aufruf mit 401 ab,
# bevor die Function überhaupt läuft — und `cron.job_run_details` meldet
# trotzdem „succeeded", weil pg_net den Auftrag ja erfolgreich abgesetzt hat.
#
# Genau so lagen die Live-Punkte am 11.09.2026 einen ganzen Spieltag lang still
# (siehe CLAUDE.md, „Ein Deploy ohne --no-verify-jwt legt den Cron still").
#
# Erwartet wird **403** aus der Function selbst (ihre eigene Secret-Prüfung),
# nicht 401 vom Gateway. Aufruf:  bash tools/sync_torwaechter.sh
set -u
cd "$(dirname "$0")/.." || exit 1
set -a && . ./supabase/.env.local && set +a

fehler=0
for f in sync-stats sync-fixtures sync-predicted-lineups sync-absences sync-squads; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    "$SUPABASE_URL/functions/v1/$f" \
    -H 'x-sync-secret: absichtlich-falsch' -H 'Content-Type: application/json' -d '{}')
  if [ "$code" = "403" ]; then
    printf '  ok   %-24s 403 (eigene Secret-Prüfung)\n' "$f"
  elif [ "$code" = "401" ]; then
    printf '  FEHL %-24s 401 — ohne --no-verify-jwt ausgespielt, der Cron kommt nicht durch\n' "$f"
    fehler=1
  else
    printf '  ?    %-24s HTTP %s\n' "$f" "$code"
    fehler=1
  fi
done

if [ "$fehler" -ne 0 ]; then
  echo
  echo "Beheben mit:  supabase functions deploy <name> --no-verify-jwt"
  exit 1
fi
