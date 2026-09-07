#!/bin/bash
# Optional interactive-session check: briefly opens a test menu-bar panel.
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_POPOVER_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_POPOVER_TMP"' EXIT
swiftc Sources/CodexTaskMonitor/TaskPopover.swift Tests/PopoverChecks/main.swift -o "$TASK_POPOVER_TMP/check"
"$TASK_POPOVER_TMP/check"
