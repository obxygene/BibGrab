#!/bin/bash
# Rebuild BibGrab and restart the running copy.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/BibGrab.app"

BIBGRAB_OUTPUT_APP="$APP" bash "$DIR/build.sh"

osascript -e 'tell application "BibGrab" to quit' 2>/dev/null || true
sleep 1
# `|| true` matters: pgrep exits 1 when nothing matches, which under
# `set -e` would abort the script before the relaunch below.
for pid in $(pgrep -f 'BibGrab.app/Contents/MacOS/BibGrab' || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 1

open "$APP"
sleep 2

if pgrep -f 'BibGrab.app/Contents/MacOS/BibGrab' >/dev/null; then
  echo "BibGrab restarted."
else
  echo "WARNING: BibGrab did not come back up — run 'open $APP' manually."
fi
