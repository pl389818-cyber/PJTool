#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="/private/tmp/pjtool-logic-$(date +%s)-$$"
mkdir -p "$TMP_DIR"
RUNNER_BIN="$TMP_DIR/logic_checks"

swiftc -parse-as-library \
  -module-cache-path "$TMP_DIR/swift-module-cache" \
  "$ROOT_DIR/PJTool/Models/PiPAspectRatio.swift" \
  "$ROOT_DIR/PJTool/Models/PiPLayoutState.swift" \
  "$ROOT_DIR/PJTool/Models/PiPGeometry.swift" \
  "$ROOT_DIR/PJTool/Models/PiPAudioPreviewConfig.swift" \
  "$ROOT_DIR/PJTool/Models/FaceFramingKeyframe.swift" \
  "$ROOT_DIR/PJTool/Models/PiPFramingKeyframeNormalizer.swift" \
  "$ROOT_DIR/PJTool/Models/CompositionProject.swift" \
  "$ROOT_DIR/PJTool/Models/TrimModels.swift" \
  "$ROOT_DIR/PJTool/Models/CameraSource.swift" \
  "$ROOT_DIR/PJTool/Models/AudioInputSource.swift" \
  "$ROOT_DIR/PJTool/Services/CompositionExportEngine.swift" \
  "$ROOT_DIR/PJTool/Services/ImportCompositeEngine.swift" \
  "$ROOT_DIR/PJTool/Services/TrimExportEngine.swift" \
  "$ROOT_DIR/Scripts/logic_checks.swift" \
  -o "$RUNNER_BIN"

"$RUNNER_BIN"
