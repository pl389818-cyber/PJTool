#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.DerivedDataLocal}"
LEGACY_DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
FRESH_BUILD="${FRESH_BUILD:-0}"
RUN_AFTER_BUILD="${RUN_AFTER_BUILD:-0}"

usage() {
  cat <<'EOF'
Usage: Scripts/run_build.sh [--fresh] [--run] [xcodebuild action ...]

Options:
  --fresh    Remove current derived data path before building.
  --run      Launch the newly built app from current derived data path.
  -h, --help Show this help.

Examples:
  Scripts/run_build.sh
  Scripts/run_build.sh --fresh
  Scripts/run_build.sh --run
  Scripts/run_build.sh --fresh clean build
EOF
}

BUILD_ACTIONS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh)
      FRESH_BUILD=1
      shift
      ;;
    --run)
      RUN_AFTER_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  BUILD_ACTIONS=("$@")
fi

if [[ ${#BUILD_ACTIONS[@]} -eq 0 ]]; then
  BUILD_ACTIONS=(build)
fi

if [[ "$FRESH_BUILD" == "1" ]]; then
  if [[ -z "$DERIVED_DATA_PATH" || "$DERIVED_DATA_PATH" == "/" ]]; then
    echo "Refusing to remove invalid DERIVED_DATA_PATH: '$DERIVED_DATA_PATH'" >&2
    exit 1
  fi
  echo "[run_build] --fresh enabled, removing: $DERIVED_DATA_PATH"
  rm -rf "$DERIVED_DATA_PATH"

  if [[ "$LEGACY_DERIVED_DATA_PATH" != "$DERIVED_DATA_PATH" && -d "$LEGACY_DERIVED_DATA_PATH" ]]; then
    echo "[run_build] removing legacy derived data: $LEGACY_DERIVED_DATA_PATH"
    rm -rf "$LEGACY_DERIVED_DATA_PATH"
  fi
fi

mkdir -p "$DERIVED_DATA_PATH"

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

if [[ "$RUN_AFTER_BUILD" == "1" ]]; then
  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/PJTool.app"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "[run_build] build finished, but app not found at: $APP_PATH" >&2
    exit 1
  fi
  echo "[run_build] launching app: $APP_PATH"
  open -na "$APP_PATH"
fi
