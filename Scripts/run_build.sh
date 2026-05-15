#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.DerivedDataLocal}"

mkdir -p "$DERIVED_DATA_PATH"

if [[ $# -eq 0 ]]; then
  BUILD_ACTIONS=(build)
else
  BUILD_ACTIONS=("$@")
fi

XCODE_ARGS=(
  -project "$ROOT_DIR/PJTool.xcodeproj"
  -scheme PJTool
  -destination "platform=macOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ -n "${CONFIGURATION:-}" ]]; then
  XCODE_ARGS+=(-configuration "$CONFIGURATION")
fi

xcodebuild "${XCODE_ARGS[@]}" "${BUILD_ACTIONS[@]}"
