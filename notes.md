# Notes: PRD Gap Analysis

## Sources

### Source 1: `prd.md`
- Type: local PRD
- Notes:
  - PRD scope covers capture, overlay interaction, OCR, pin, color picker, measurement, editing, recording, output strategy, history/search, cloud sharing, and UX constraints.
  - MVP explicitly requires full screen, area, window, floating preview, basic annotation, copy/save/share, multi-display, history, OCR, and hotkeys.

### Source 2: `README.md`
- Type: local feature summary
- Notes:
  - Declares many features as implemented, including window screenshot, ruler, history, OCR, and hotkeys.
  - Some README claims do not match reachable functionality in code.

### Source 3: Repository implementation
- Type: local source code
- Notes:
  - Capture entry points live in `Sources/App/AppCoordinator.swift`, `Sources/App/MenuBarController.swift`, and `Sources/Hotkeys/HotkeyManager.swift`.
  - Overlay and selection logic live in `Sources/Capture/RegionSelectionController.swift` and `Sources/Capture/RegionSelectionView.swift`.
  - Output/history/OCR/editor live in `Sources/Editor`, `Sources/OCR`, `Sources/History`, and `Sources/Services`.

## Synthesized Findings

### Missing features
- No recording pipeline at all: no region/full-screen recording, no system audio or mic recording, no GIF/video export.
- No delayed screenshot mode.
- No optional freeze-screen capture mode.
- No automatic sensitive-info masking.
- No history search by OCR/app/tag and no metadata index for that.
- No sharing panel and no configurable output strategy memory.
- No protected-window or DRM-specific user-facing error handling.
- No old-macOS fallback path; implementation is ScreenCaptureKit-only.

### Partial implementations with major PRD gaps
- Full-screen capture only captures the display under the mouse, not all displays or per-display outputs.
- Window capture exists in lower layers but has no dedicated user entry point; area mode click-to-window is the only reachable path.
- Area overlay lacks magnifier, pt+px size display, selection move/resize modifiers, and precision affordances required by PRD.
- Scrolling capture is manual-scroll plus timer sampling, not automatic scrolling with robustness for sticky headers or lazy loading.
- OCR returns plain text only; no bounding boxes, highlighting, or click-to-copy blocks.
- Pin window is basic; no transparency, click-through, always-on-top controls, or display targeting.
- Color picker only copies HEX; no RGB/HSL/P3/sRGB output options.
- Undo is only “remove last annotation”; there is no redo or full history stack.

### Code/README inconsistencies
- README says window capture has a dedicated shortcut, but `HotkeyManager` has no window-capture action.
- README says ruler exists, but `RulerWindowController` has no menu or hotkey entry point in the app coordinator.
- README says hotkeys are `⇧⌘1-4 / ⇧⌘P / ⇧⌘R`, but code defines area/full/scroll/color-picker/OCR and omits window/ruler.
