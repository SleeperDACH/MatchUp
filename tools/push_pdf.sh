#!/bin/sh
# Baut PUSH.pdf und PUSH-OFFEN.pdf aus den Quellen in docs/.
#
# **Warum es dieses Skript gibt.** Die erste Fassung der beiden PDFs entstand
# aus HTML-Dateien im Arbeitsverzeichnis des Agenten — das wird zwischen
# Sitzungen geleert. Danach lagen die PDFs im Repo, ließen sich aber nicht mehr
# erzeugen und veralteten still: Sie zeigten tagelang einen Schritt als offen,
# der längst erledigt war. Ein Artefakt ohne Quelle ist totes Gewicht.
#
# Gerendert wird mit Chrome im Kopflosmodus — das ist dieselbe Engine, die die
# Seite auch am Bildschirm zeigt, und sie beherrscht `@page`, `break-before`
# und die eingebettete Rajdhani. Ein eigener PDF-Setzer wäre eine zweite
# Abhängigkeit für ein Dokument, das zweimal im Jahr gebaut wird.
#
#   Aufruf:  tools/push_pdf.sh
#   Prüfen:  Seitenzahl und Größe werden am Ende ausgegeben.

set -eu

wurzel=$(cd "$(dirname "$0")/.." && pwd)
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [ ! -x "$chrome" ]; then
  echo "Chrome nicht gefunden: $chrome" >&2
  echo "Ohne Chrome kein PDF — die Quellen in docs/ bleiben trotzdem lesbar." >&2
  exit 1
fi

bauen() {
  quelle="$1"
  ziel="$2"
  [ -f "$wurzel/$quelle" ] || { echo "fehlt: $quelle" >&2; exit 1; }
  # --virtual-time-budget: Chrome wartet, bis die Schriften geladen sind.
  # Ohne das steht die Seite gelegentlich in der Systemschrift im PDF.
  "$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
    --virtual-time-budget=6000 \
    --print-to-pdf="$wurzel/$ziel" "file://$wurzel/$quelle" 2>/dev/null
  echo "  $ziel"
}

echo "Baue aus docs/ …"
bauen "docs/push.html"       "PUSH.pdf"
bauen "docs/push_offen.html" "PUSH-OFFEN.pdf"

echo
echo "Ergebnis:"
for f in PUSH.pdf PUSH-OFFEN.pdf; do
  python3 - "$wurzel/$f" <<'PY'
import re, sys
p = sys.argv[1]
d = open(p, 'rb').read()
seiten = len(re.findall(rb'/Type\s*/Page[^s]', d))
print(f"  {p.split('/')[-1]}: {seiten} Seiten, {round(len(d)/1024)} KB")
PY
done
