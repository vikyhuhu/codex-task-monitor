#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${CODEX_MONITOR_BUILD_SYSTEM:-}" ]]; then
    swift build --build-system "$CODEX_MONITOR_BUILD_SYSTEM" -c release
else
    swift build -c release
fi
APP="$PWD/dist/Codex Task Monitor.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CodexTaskMonitor "$APP/Contents/MacOS/CodexTaskMonitor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codex-task-monitor</string>
<key>CFBundleName</key><string>Codex Task Monitor</string>
<key>CFBundleDisplayName</key><string>Codex Task Monitor</string>
<key>CFBundleExecutable</key><string>CodexTaskMonitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/CodexTaskMonitor-macOS.zip"
printf 'Built: %s\n' "$APP"
