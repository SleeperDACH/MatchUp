#!/bin/zsh
# Startet die App mit Supabase-Anbindung (Keys aus supabase/.env.local).
# Verwendung: ./run_dev.sh [weitere flutter-run-Argumente, z. B. -d macos]
set -e
cd "$(dirname "$0")"
source <(grep -E '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY)=' supabase/.env.local | sed 's/^/export /')
exec flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  "$@"
