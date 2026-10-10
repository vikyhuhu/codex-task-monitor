#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
LOGIN_ITEM_TMP=$(mktemp -d)
trap 'rm -rf "$LOGIN_ITEM_TMP"' EXIT
swiftc Sources/CodexTaskMonitor/LoginItemController.swift Tests/LoginItemChecks/main.swift -o "$LOGIN_ITEM_TMP/check"
"$LOGIN_ITEM_TMP/check"
