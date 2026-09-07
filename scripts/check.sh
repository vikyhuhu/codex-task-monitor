#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run MonitorCoreChecks
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Codex Task Monitor.app"
plutil -lint "dist/Codex Task Monitor.app/Contents/Info.plist"
