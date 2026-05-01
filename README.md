# PJTool

PJTool is a macOS utility suite with three fixed modules:

- Recording
- PiP Camera
- Video Processing

The current product direction keeps the existing recording and video-processing semantics intact while aligning:

- PiP Camera with a native macOS floating camera utility
- Recording with a QuickTime-style whole-screen recorder for the primary display

See [SPEC.md](/Users/jamie/CodexAi/pjtool/PJTool/SPEC.md) and [AGENTS.md](/Users/jamie/CodexAi/pjtool/PJTool/AGENTS.md) for the latest product and implementation constraints.

## Modules

### Recording

- Records the macOS primary display only
- Does not support region capture, selection rectangles, or fixed dashed capture frames
- Hides the main window immediately after recording starts
- Uses a separate floating controller for stop actions instead of reusing the PiP window
- Restores the main window after normal stop, startup failure, or unexpected termination
- Keeps recording microphone selection and live monitoring inside the Recording module
- Tries to exclude PJTool windows from ScreenCaptureKit capture and shows a readable warning if exclusion fails

### PiP Camera

- Independent floating camera tool, not a recording side panel
- Designed as a control console for low-latency, stable desktop picture-in-picture preview
- Supports always-on-top preview across Spaces and full-screen contexts
- Supports manual video and audio device selection, including iPhone Continuity when available
- Supports preview mute and real-time microphone level monitoring
- Supports `Auto`, `16:9`, and `4:3` aspect ratios
- Keeps height stable when switching between `16:9` and `4:3`
- Uses `Auto` sizing to prioritize visibility and dragability on screen
- Starts disabled by default with `enableCameraPiP = false`
- Does not automatically open preview on cold launch
- Uses `bootstrap()` only for device refresh and state sync, not automatic preview startup

The PiP page intentionally does not include:

- recording
- export
- speech transcription

### Video Processing

- Preserves timeline-insertion stitching semantics rather than overlay composition
- Supports inserting imported clips at arbitrary timestamps
- Supports multi-range trim using a delete-segment model
- Supports export and validation reports

## UI and State Rules

- The left sidebar launches at `200 px`
- Startup must force the default sidebar width instead of restoring stale split-view widths
- The sidebar can be resized, but not below `200 px`
- Recording status is written only to `statusMessage`
- PiP status is written only to `pipStatusMessage`
- PiP actions must not overwrite the main recording status
- The menu bar can present Recording and PiP states at the same time

## Permissions

PJTool may request access to:

- Screen Recording
- Camera
- Microphone

The app should not fail silently when permissions are missing, no compatible devices are available, or a selected device goes offline.

## Implementation Expectations

- PiP window behavior should include `canJoinAllSpaces`, `fullScreenAuxiliary`, and `moveToActiveSpace`
- PiP preview should use `orderFrontRegardless` as a fallback after Space or app-activation changes
- Device discovery should prefer `AVCaptureDevice.DiscoverySession` and fall back to the legacy API when needed
- Offline devices should fail gracefully, fall back when possible, and present a readable status to the user

## Tech Stack

- SwiftUI for the main console UI
- AppKit for floating window and panel behavior
- AVFoundation for camera and audio device handling
- ScreenCaptureKit for display recording

## Repository Layout

```text
.
├── AGENTS.md
├── PJTool.xcodeproj
├── PJTool/        # App source
├── Scripts/       # Logic checks and smoke scripts
└── SPEC.md
```

## Build and Checks

Run the minimum required checks from the repository root:

```bash
xcodebuild -project PJTool.xcodeproj -scheme PJTool -destination 'platform=macOS' build
Scripts/run_logic_checks.sh
```

Additional validation helpers are available in `Scripts/`, including `run_validation_smoke.sh`, `run_pipeline_smoke.sh`, and `run_device_diagnostics.sh`.

## Contributor Notes

- Preserve the three-module product boundary
- Do not turn PiP Camera into a recording settings page
- Do not reintroduce region capture
- Do not change video stitching from timeline insertion to overlay semantics
- Keep documentation aligned with the latest `SPEC.md` and `AGENTS.md`
