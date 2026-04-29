#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_VIDEO="${1:-}"
TMP_DIR="/private/tmp/pjtool-validation-$(date +%s)-$$"
mkdir -p "$TMP_DIR"
REPORT_DIR="${2:-$TMP_DIR}"
RUNNER_BIN="$TMP_DIR/validation_smoke"

swiftc -parse-as-library \
  -module-cache-path "$TMP_DIR/swift-module-cache" \
  "$ROOT_DIR/PJTool/Models/CameraSource.swift" \
  "$ROOT_DIR/PJTool/Models/AudioInputSource.swift" \
  "$ROOT_DIR/PJTool/Models/ValidationReport.swift" \
  "$ROOT_DIR/PJTool/Services/ValidationService.swift" \
  "$ROOT_DIR/Scripts/validation_smoke.swift" \
  -o "$RUNNER_BIN"

if [[ -n "$OUTPUT_VIDEO" ]]; then
  "$RUNNER_BIN" --output "$OUTPUT_VIDEO" --report-dir "$REPORT_DIR"
else
  "$RUNNER_BIN" --report-dir "$REPORT_DIR"
fi
