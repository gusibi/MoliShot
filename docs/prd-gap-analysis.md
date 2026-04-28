# PRD Gap Analysis

## Scope and Method

This analysis compares `prd.md` with the current repository implementation. I treated source code as the source of truth and used `README.md` only as a secondary signal, because some README claims do not match the reachable product behavior.

Key files inspected:
- `Sources/App/AppCoordinator.swift`
- `Sources/App/MenuBarController.swift`
- `Sources/Hotkeys/HotkeyManager.swift`
- `Sources/Capture/ScreenCaptureService.swift`
- `Sources/Capture/RegionSelectionController.swift`
- `Sources/Capture/RegionSelectionView.swift`
- `Sources/Capture/ScrollingCaptureController.swift`
- `Sources/Editor/EditorWindowController.swift`
- `Sources/Editor/EditorView.swift`
- `Sources/OCR/OCRService.swift`
- `Sources/History/HistoryStore.swift`
- `Sources/History/HistoryWindowController.swift`
- `Sources/Pin/PinWindowController.swift`
- `Sources/Ruler/RulerWindowController.swift`
- `Sources/Services/UploadService.swift`

## Executive Summary

The current app already has a usable baseline for area capture, single-display full-screen capture, editor-based annotation, plain-text OCR, upload, pinning, and local history. But it is still far from the PRD scope.

The largest gaps are:
- recording is completely absent
- delayed capture is absent
- floating preview and configurable output strategy are absent
- history search and OCR-structured indexing are absent
- many “professional interaction” details in the capture overlay are absent
- several features claimed in README are not actually reachable from the app

## 1. Missing Features

These are in the PRD but not implemented in the current codebase.

### 1.1 Recording

PRD:
- region recording
- full-screen recording
- window recording
- system audio and microphone capture
- GIF / short-video export

Current implementation:
- no recording coordinator, service, UI, menu entry, hotkey, or export pipeline
- no `SCStream` recording flow
- no `AVAssetWriter`
- no GIF export path

Conclusion:
- PRD sections 18 and 19 are fully missing.

### 1.2 Delayed Capture

PRD:
- 3s / 5s / 10s delay

Current implementation:
- no timer-based screenshot mode exposed in app flow

Conclusion:
- PRD section 4 is missing.

### 1.3 Freeze-Screen Mode

PRD:
- optional freeze mode for selecting on a static frame

Current implementation:
- no separate “freeze then select” mode
- `RegionSelectionController` pre-captures snapshots only to avoid overlay contamination in the final image; it does not show a frozen screen UI to the user

Conclusion:
- PRD section 8 is missing.

### 1.4 Sensitive Data Auto-Redaction

PRD:
- OCR + rules to detect phone/email/address/order number and suggest masking

Current implementation:
- no rule engine
- no mask suggestions based on OCR output

Conclusion:
- PRD section 17 is missing.

### 1.5 History Search and Structured Indexing

PRD:
- search by time, OCR text, app name, tag

Current implementation:
- `HistoryStore` only persists `id`, `filename`, `timestamp`
- no OCR metadata, no app metadata, no tags, no search UI

Conclusion:
- PRD section 21 is mostly missing.

### 1.6 Output Strategy / Floating Preview Workflow

PRD:
- output actions should be combinable
- app should remember the last output strategy
- default floating preview with fast actions

Current implementation:
- every capture goes straight to `handleCapturedImage()` and then opens the full editor
- no floating preview controller
- no output-rule configuration
- no “remember last output strategy”

Conclusion:
- PRD section 20 and the “截图后” UX spec are not implemented as designed.

### 1.7 Compatibility Fallback

PRD:
- old macOS fallback via `CGWindowListCreateImage`

Current implementation:
- capture stack is fully ScreenCaptureKit-based
- no availability split or fallback path

Conclusion:
- PRD section 5 is missing.

### 1.8 Protected/DRM Window User Feedback

PRD:
- clear error prompts for protected windows / black screens / privacy content

Current implementation:
- capture failures are mostly logged with `NSLog`
- no dedicated user-facing explanation for protected window cases

Conclusion:
- compatibility/error-handling requirements are missing at the product layer.

## 2. Implemented But Different From PRD

These features exist, but the behavior or scope does not match the PRD.

### 2.1 Full-Screen Capture

PRD expectation:
- support single-display or multi-display capture
- in multi-display mode, each display can output independently

Current implementation:
- `captureFullScreen()` calls `captureDisplayUnderMouse()`
- only one display is captured per invocation

Impact:
- does not satisfy the PRD’s multi-display/full-screen scope.

### 2.2 Window Capture

PRD expectation:
- dedicated window capture mode with hover highlight and click capture

Current implementation:
- low-level window capture exists
- user-facing flow does not expose dedicated window mode
- area mode can silently fall back to window capture if the user clicks without dragging on a hovered window

Impact:
- feature exists technically, but the product surface is not aligned with the PRD.

### 2.3 Area Selection Overlay

PRD expectation:
- crosshair
- drag select
- move selection with Space
- aspect lock with Shift
- center-resize with Option
- magnifier
- pt + px size display
- precision-oriented selection workflow

Current implementation:
- crosshair exists
- drag selection exists
- hovered window outline exists
- size label exists, but only as raw rect dimensions from the overlay
- no magnifier rendering
- no pt + px dual display
- no modifier-key behaviors for move/lock-ratio/center-resize
- no post-draw selection adjust handles or move-resize loop

Impact:
- core area capture works, but much of the PRD’s “professional precision” interaction is absent.

### 2.4 Menu / Popover Preservation

PRD expectation:
- try to keep menus/popovers/tooltips open, ideally via `CGEventTap`

Current implementation:
- uses `HotKey` and non-activating overlay panels
- no `CGEventTap`
- no accessibility/input interception path

Impact:
- behavior may be acceptable in some cases, but it is not implemented in the stronger PRD-prescribed way.

### 2.5 Scrolling Capture

PRD expectation:
- automatic scrolling + continuous capture + stitching
- handle sticky headers, floating sidebars, lazy loading, scroll jitter

Current implementation:
- user manually scrolls
- app samples the selected rect on a timer
- frame alignment uses `VNTranslationalImageRegistrationRequest`
- no automated scroll driver
- no specific sticky-header/lazy-load handling beyond a simple ROI heuristic

Impact:
- current solution is a baseline prototype, not the robust PRD-level scrolling capture.

### 2.6 OCR

PRD expectation:
- text extraction
- text block highlighting
- click-to-copy by block/line/word

Current implementation:
- `OCRService` returns plain joined text only
- `OCRWindowController` shows editable text and copies it to clipboard
- no bounding boxes, no overlay highlights, no structured selection

Impact:
- OCR exists, but only the lowest-level text output is present.

### 2.7 Pin Window

PRD expectation:
- pin to top
- scale
- transparency
- click-through
- display targeting

Current implementation:
- floating pin window exists
- draggable image exists
- hover toolbar provides close/copy/save/OCR
- no transparency controls
- no click-through mode
- no monitor affinity or placement rules

Impact:
- useful baseline, but much narrower than the PRD.

### 2.8 Color Picker

PRD expectation:
- HEX, RGB, HSL, Display P3, sRGB

Current implementation:
- uses `NSColorSampler`
- copies only HEX string

Impact:
- PRD section 13 is only partially implemented.

### 2.9 Measurement

PRD expectation:
- width/height, spacing, alignment guides, optional auto-snapping to UI edges
- possibly use Accessibility API + image edge detection

Current implementation:
- `RulerWindowController` measures distance, dx, dy, angle
- no object spacing detection
- no alignment guide computation
- no accessibility integration

Impact:
- this is closer to a ruler/protractor utility than the PRD’s UI measurement system.

### 2.10 Annotation Undo/Redo

PRD expectation:
- full edit history using `UndoManager`

Current implementation:
- `EditorView.undo()` only removes the last annotation or cancels the current interaction
- no redo
- no operation-based history

Impact:
- PRD section 16 is only minimally implemented.

## 3. Reachability and Product Surface Problems

These are important because they affect what the user can actually use, even if some lower-level code exists.

### 3.1 Window Capture Has No Proper Entry Point

Evidence:
- `AppCoordinator` exposes `captureArea()`, `captureFullScreen()`, `captureScrolling()`, `openColorPicker()`, `runScreenOCR()`, `openHistory()`, `openPreferences()`
- there is no `captureWindow()` entry point
- `MenuBarController` has no window-capture menu item
- `HotkeyManager.HotkeyAction` has no window-capture action

Conclusion:
- window capture is not shipped as a first-class user feature.

### 3.2 Ruler Exists in Code but Is Not Wired Into the App

Evidence:
- `RulerWindowController.swift` exists
- no usage of `RulerWindowController` anywhere else in `Sources/`
- no app coordinator method to open it
- no menu item or hotkey for it

Conclusion:
- README says ruler exists, but current app surface does not expose it.

### 3.3 Hotkey Mapping Does Not Match README

README says:
- `⇧⌘1` area
- `⇧⌘2` window
- `⇧⌘3` full screen
- `⇧⌘4` scrolling
- `⇧⌘P` color picker
- `⇧⌘R` ruler

Code says:
- area
- full screen
- scrolling
- color picker
- OCR

Also:
- `HotkeyAction.ocr = "ruler"` is a naming/storage mismatch and suggests an unfinished rename

Conclusion:
- public feature claims and current input wiring are inconsistent.

## 4. UX Differences From PRD

### 4.1 Permission Experience

PRD expectation:
- only ask when needed
- avoid stacking intrusive prompts on first launch

Current implementation:
- app does not auto-call `CGRequestScreenCaptureAccess()`, which is good
- but `AppDelegate` opens Preferences automatically on launch when permission is missing

Conclusion:
- this is less intrusive than auto-requesting permission, but still more proactive than the PRD’s “only when capability is triggered” guidance.

### 4.2 Post-Capture Flow

PRD expectation:
- quick floating preview
- one-click copy/pin/share/annotate/delete

Current implementation:
- capture goes directly into editor and history storage
- no lightweight preview layer

Conclusion:
- the current flow is heavier than the PRD’s fast-path design.

### 4.3 Non-Intrusive Capture Principle

PRD expectation:
- do not disturb the target app more than necessary

Current implementation:
- overlay uses `NSPanel` and avoids activation during selection, which aligns with the PRD
- but after capture the app force-activates its editor window

Conclusion:
- capture-time behavior is partly aligned; post-capture behavior is more intrusive than the PRD ideal.

## 5. Priority View

If the goal is to close the biggest PRD gaps with the least ambiguity, the current missing items break down like this:

### Highest product gaps
- recording pipeline
- floating preview and output strategy model
- dedicated window capture entry point
- full-screen multi-display behavior
- history search/indexing

### High interaction/quality gaps
- area overlay precision features
- stronger menu/popover preservation strategy
- scrolling capture robustness
- full undo/redo
- OCR bounding-box interaction

### Medium gaps
- freeze mode
- delayed capture
- richer pin controls
- richer color formats
- protected-window user messaging

## 6. Bottom Line

The repository is best described as a good baseline screenshot app, not yet a PRD-complete MoliShot.

What is already solid:
- one-shot ScreenCaptureKit-based capture foundation
- basic area capture and editor flow
- plain-text OCR
- upload and pin primitives
- local history persistence

What is still materially missing relative to the PRD:
- recording
- delay/freeze workflows
- preview/output workflow
- history searchability
- several advanced interaction details
- several features that are present in README but not actually reachable in the app
