# PJTool

PJTool is a macOS utility suite with four fixed modules:

1. Recording
2. PiP Camera
3. Screen Drawing
4. Video Cutting

For implementation constraints and product rules, see:

- [SPEC.md](/Users/jamie/CodexAi/pjtool/SPEC.md)
- [AGENTS.md](/Users/jamie/CodexAi/pjtool/AGENTS.md)

## Module Overview

### 1) Recording

- QuickTime-style primary-display full-screen recording
- Region recording is intentionally removed
- Main window auto-hides after recording starts
- Uses a dedicated floating recording controller for stop action
- Restores main window on normal stop, startup failure, or unexpected stop

### 2) PiP Camera

- Independent floating camera utility (not a recording side panel)
- Always-on-top preview across Spaces/full-screen contexts
- Manual video/audio device selection (including Continuity Camera when available)
- Preview mute and real-time microphone level feedback
- Aspect ratio: `Auto / 16:9 / 4:3`
- Global hotkey: `⌘⌥P` (toggle show/hide)

### 3) Screen Drawing

- Decoupled drawing module with floating toolbar + transparent canvas
- 6 tools: line, arrow, rectangle, ellipse, cross, check
- 5 color presets: `1 red / 2 yellow / 3 green / 4 blue / 5 black`
- Unified dismissal animation pipeline for clear/hide
- Animation modes: `Random` or `Fixed`
- Fixed effects: `Scatter & Fall`, `Left→Right`, `Right→Left`, `Top→Bottom`, `Bottom→Top`

Current drawing hotkeys:

- `⌃⌥1~5`: select color presets
- `⌘⌥1~6`: select drawing tools
- `⌘⌃S`: toggle drawing overlay show/hide
- `⌘⌃X`: toggle canvas passthrough/drawing interaction

### 4) Video Cutting

- Popup-based smart cutting workflow
- Drag-and-drop or file import for `.mp4/.mov`
- Timeline trimming, multi-range deletion, crop, audio denoise/EQ, export
- Keeps pause state after import/reload (no forced autoplay)

## State Isolation Rules

- Recording writes only `statusMessage`
- PiP writes only `pipStatusMessage`
- Screen Drawing writes only `drawStatusMessage`
- PiP and Screen Drawing actions must not override recording status text

## Permissions

PJTool may request:

- Screen Recording
- Camera
- Microphone

If global hotkeys are unavailable due to system constraints, the app falls back to foreground handling with readable status guidance.

## Build & Checks

From `/Users/jamie/CodexAi/pjtool/PJTool`:

```bash
xcodebuild -project PJTool.xcodeproj -scheme PJTool -destination 'platform=macOS' build
Scripts/run_logic_checks.sh
```

## Repo Layout

```text
├── 
└── PJTool/
    ├── AGENTS.md
    ├── SPEC.md
    ├── PJTool.xcodeproj
    ├── PJTool/
    └── Scripts/
```
