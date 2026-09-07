#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
DEST="$HOME/Applications/Codex Task Monitor.app"
mkdir -p "$HOME/Applications"
# Stop only our app when replacing an existing installation.
if pgrep -x CodexTaskMonitor >/dev/null; then pkill -x CodexTaskMonitor || true; fi
/usr/bin/ditto "dist/Codex Task Monitor.app" "$DEST"
open "$DEST"
printf 'Installed and started: %s\n' "$DEST"
