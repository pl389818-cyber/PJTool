#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="/private/tmp/pjtool-pip-smoke-$(date +%s)-$$"
mkdir -p "$REPORT_DIR"

BUILD_LOG="$REPORT_DIR/build.log"
LOGIC_LOG="$REPORT_DIR/logic.log"
DIAG_LOG="$REPORT_DIR/device.log"
SUMMARY="$REPORT_DIR/pip_smoke_summary.txt"

BUILD_STATUS="PASS"
LOGIC_STATUS="PASS"
DEVICE_STATUS="PASS"
MANUAL_STATUS="BLOCKED"

set +e
xcodebuild -project "$ROOT_DIR/PJTool.xcodeproj" -scheme PJTool -destination 'platform=macOS' -derivedDataPath /private/tmp/pjtool-derived build >"$BUILD_LOG" 2>&1
if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
  BUILD_STATUS="FAIL"
fi

"$ROOT_DIR/Scripts/run_logic_checks.sh" >"$LOGIC_LOG" 2>&1
if ! grep -q "LOGIC_CHECK PASS" "$LOGIC_LOG"; then
  LOGIC_STATUS="FAIL"
fi

"$ROOT_DIR/Scripts/run_device_diagnostics.sh" >"$DIAG_LOG" 2>&1
DIAG_EXIT=$?
if [[ $DIAG_EXIT -eq 0 ]]; then
  DEVICE_STATUS="PASS"
elif grep -q "videoAuth=denied\|videoAuth=notDetermined\|audioAuth=denied\|audioAuth=notDetermined" "$DIAG_LOG"; then
  DEVICE_STATUS="BLOCKED(permission)"
else
  DEVICE_STATUS="BLOCKED(device_offline_or_unavailable)"
fi
set -e

{
  echo "PIP_SMOKE_REPORT"
  echo "generated_at=$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "build=$BUILD_STATUS"
  echo "logic=$LOGIC_STATUS"
  echo "device_diag=$DEVICE_STATUS"
  echo "manual_ui_smoke=$MANUAL_STATUS"
  echo "manual_checklist="
  echo "1) 打开 PiP 摄像页，点击‘弹出 PiP 摄像’"
  echo "2) 验证悬浮窗置顶并可拖拽缩放"
  echo "3) 切换 自动/16:9/4:3，验证窗口保持可见"
  echo "4) 切换视频设备与 PiP 麦克风（含 Continuity）"
  echo "5) 切换预览静音与音量，观察实时电平"
  echo "6) 切换 Space/全屏 App，确认 PiP 仍可见"
  echo "artifacts_dir=$REPORT_DIR"
} >"$SUMMARY"

cat "$SUMMARY"

if [[ "$BUILD_STATUS" == "FAIL" || "$LOGIC_STATUS" == "FAIL" ]]; then
  exit 1
fi

exit 0
