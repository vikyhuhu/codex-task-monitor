#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
DEST="$HOME/Applications/Codex Task Monitor.app"
mkdir -p "$HOME/Applications"
# Stop only our app when replacing an existing installation.
if pgrep -x CodexTaskMonitor >/dev/null; then
    pkill -x CodexTaskMonitor || true
    # LaunchServices may otherwise try to reopen the instance still terminating.
    for ((attempt = 0; attempt < 50; attempt++)); do
        if ! pgrep -x CodexTaskMonitor >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -x CodexTaskMonitor >/dev/null; then
        printf 'Could not stop the existing monitor; quit it and retry.\n' >&2
        exit 1
    fi
fi
/usr/bin/ditto "dist/Codex Task Monitor.app" "$DEST"
open "$DEST" --args --show
printf 'Installed and started: %s\n' "$DEST"
