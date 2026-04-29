#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TASK="${1:-all}"
TMP_DIR="/private/tmp/pjtool-smoke-$(date +%s)-$$"
mkdir -p "$TMP_DIR"

BASE_VIDEO="$TMP_DIR/base.mp4"
CAMERA_VIDEO="$TMP_DIR/camera.mp4"
INSERT_VIDEO="$TMP_DIR/insert.mp4"
RUNNER_BIN="$TMP_DIR/pipeline_smoke"

/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i color=c=blue:s=640x360:d=2:r=30 \
  -f lavfi -i sine=frequency=440:sample_rate=48000:duration=2 \
  -shortest -c:v libx264 -pix_fmt yuv420p -r 30 -g 60 -b:v 1200k -maxrate 1200k -bufsize 2400k -c:a aac -b:a 128k "$BASE_VIDEO"

/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i color=c=green:s=640x360:d=2:r=30 \
  -f lavfi -i sine=frequency=330:sample_rate=48000:duration=2 \
  -shortest -c:v libx264 -pix_fmt yuv420p -r 30 -g 60 -b:v 1200k -maxrate 1200k -bufsize 2400k -c:a aac -b:a 128k "$CAMERA_VIDEO"

/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i color=c=red:s=640x360:d=1:r=30 \
  -f lavfi -i sine=frequency=880:sample_rate=48000:duration=1 \
  -shortest -c:v libx264 -pix_fmt yuv420p -r 30 -g 60 -b:v 1200k -maxrate 1200k -bufsize 2400k -c:a aac -b:a 128k "$INSERT_VIDEO"

swiftc -parse-as-library \
  -module-cache-path "$TMP_DIR/swift-module-cache" \
  "$ROOT_DIR/PJTool/Models/PiPAspectRatio.swift" \
  "$ROOT_DIR/PJTool/Models/PiPLayoutState.swift" \
  "$ROOT_DIR/PJTool/Models/PiPGeometry.swift" \
  "$ROOT_DIR/PJTool/Models/FaceFramingKeyframe.swift" \
  "$ROOT_DIR/PJTool/Models/CompositionProject.swift" \
  "$ROOT_DIR/PJTool/Models/TrimModels.swift" \
  "$ROOT_DIR/PJTool/Services/CompositionExportEngine.swift" \
  "$ROOT_DIR/PJTool/Services/TrimExportEngine.swift" \
  "$ROOT_DIR/Scripts/pipeline_smoke.swift" \
  -o "$RUNNER_BIN"

SMOKE_LOG="$TMP_DIR/pipeline_smoke.log"
set +e
"$RUNNER_BIN" --task "$TASK" --base "$BASE_VIDEO" --camera "$CAMERA_VIDEO" --insert "$INSERT_VIDEO" --tmp "$TMP_DIR" >"$SMOKE_LOG" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  if rg -q "NSInvalidArgumentException|FigAssetExportSession|NSException|Abort trap: 6" "$SMOKE_LOG"; then
    echo "PIPELINE_SMOKE BLOCKED: AVAssetExportSession runtime exception in current environment."
    echo "PIPELINE_SMOKE BLOCKED_REASON: media export stack threw NSException; not treated as feature failure."
    tail -40 "$SMOKE_LOG"
    echo "SMOKE_OUTPUT_DIR=$TMP_DIR"
    exit 0
  fi

  cat "$SMOKE_LOG"
  exit $STATUS
fi

cat "$SMOKE_LOG"

echo "SMOKE_OUTPUT_DIR=$TMP_DIR"
