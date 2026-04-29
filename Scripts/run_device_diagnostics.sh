#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="/private/tmp/pjtool-device-diag-$(date +%s)-$$"
mkdir -p "$TMP_DIR"
RUNNER_BIN="$TMP_DIR/device_diagnostics"

swiftc -parse-as-library \
  -module-cache-path "$TMP_DIR/swift-module-cache" \
  "$ROOT_DIR/Scripts/device_diagnostics.swift" \
  -o "$RUNNER_BIN"

set +e
"$RUNNER_BIN"
RESULT=$?
set -e

if [[ $RESULT -eq 0 ]]; then
  echo "DEVICE_DIAGNOSTICS PASS"
  exit 0
fi

echo "DEVICE_DIAGNOSTICS WARN (likely blocked by permission/device environment)"
exit $RESULT
