#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${CODEX_MONITOR_BUILD_SYSTEM:-}" ]]; then
    swift run --build-system "$CODEX_MONITOR_BUILD_SYSTEM" MonitorCoreChecks
else
    swift run MonitorCoreChecks
fi
./scripts/check-login-item.sh
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Codex Task Monitor.app"
plutil -lint "dist/Codex Task Monitor.app/Contents/Info.plist"
