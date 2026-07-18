# MoliShot

English | [中文版](README_zh.md)

A macOS screenshot utility based on Swift + AppKit + ScreenCaptureKit + Vision, targeting the core features of Shottr Pro.

**Current Version**: v0.7.1 — UI & Interaction Refinement (native SwiftUI Preferences, editor swatches, crop confirmation bar, responsive toolbar).

**⚠ Status**: A functional baseline version, covering the complete screenshot workflow from the menu bar and hotkeys. Compared to mature products, some limitations remain, mainly rolling screenshot stability and OCR structured output.

## Features Implemented

| Module | Description |
| --- | --- |
| Area Screenshot | Select area on the display where the mouse is located. Supports window hover highlighting, magnifier, real-time `pt`/`px` dimensions, `Space` to move selection, `Shift` to lock aspect ratio, `Option` to scale from center, and avoids capturing overlays into the final result. |
| Fullscreen Screenshot | Capture the display where the mouse is located. |
| Scrolling Screenshot | Uses Vision `VNTranslationalImageRegistrationRequest` for frame-to-frame registration, manual scrolling + stitching. |
| Annotation Editor | Arrow, rectangle, oval, line, pen, text, counter, highlight, blur, pixelate, crop. Real undo/redo, style editing for selected annotations (color, stroke, font size, opacity, fill color), 8-handle resizing, duplicate via copy-paste, Z-ordering, adjustable blur radius, PNG/JPEG export. |
| OCR | Vision text recognition, auto-detects language. The results window supports viewing and editing, and recognized text is automatically copied to the clipboard. |
| Color Picker | System `NSColorSampler` with auto-copy to HEX + HUD notification. |
| Pin (Sticky Notes) | Float window kept on top, hover to show toolbar. |
| History | Persisted in the Application Support directory, browsing via grid layout. |
| Global Hotkeys | Prioritizes intercepting screenshot hotkeys using `CGEventTap`; automatically downgrades to HotKey when Accessibility permissions are not granted. Defaults: ⇧⌘1 / ⇧⌘3 / ⇧⌘4 / ⇧⌘P / ⇧⌘R. |
| Preferences | Shortcut list, screen recording/accessibility permission status, history path. |
| Export & Share | Clipboard, save to PNG/JPEG, upload to 0x0.st. |

## Download & Installation

### Download

Download the latest `MoliShot-vX.Y.Z.dmg` from [GitHub Releases](https://github.com/gusibi/MoliShot/releases), then drag and drop it into `/Applications`.

### DMG Unsigned: What if it is blocked on first launch?

Since MoliShot's DMG **is not signed with a developer certificate** (Gatekeeper won't allow it automatically), macOS might show one of the following prompts when double-clicking to open the app:

- **"MoliShot can't be opened because it is from an unidentified developer"**
- **"MoliShot is damaged and can't be opened"** (macOS misleading error for some unsigned apps)

Choose one of the following ways to allow it:

**Method A: Right-click to open (Simplest)**

1. Locate `MoliShot.app` in Finder.
2. **Hold the Control key and click** (or right-click) the app icon, then select **Open**.
3. Click **Open** in the confirmation dialog.

**Method B: Allow via System Settings**

1. Close the dialog after double-clicking the app and triggering the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the bottom, find the prompt about "MoliShot", and click **Open Anyway**.
4. Double-click the app to open it afterwards.

**Method C: Remove quarantine attribute via Terminal** (Suitable for the "damaged" warning)

```bash
xattr -dr com.apple.quarantine /Applications/MoliShot.app
```

After executing this, double-click the app to open it. This removes the quarantine flag macOS places on unsigned downloads and does not affect the app's functionality.

> Once allowed, the system remembers the app and won't block it again. Screen Recording and Accessibility permissions must be granted separately in System Settings (see "Usage" below).

## Build

### 1. Install XcodeGen (First time only)

```bash
brew install xcodegen
```

### 2. Generate Xcode Project

```bash
cd /path/to/MoliShot
xcodegen generate
open MoliShot.xcodeproj
```

### 3. Configure Signing in Xcode

After opening the project for the first time, go to the Target `MoliShot` → **Signing & Capabilities** panel:

- Team: Select your own Apple ID or "Sign to Run Locally"
- Bundle Identifier: Keep `com.molishot.app` or change it to your own

### 4. Run

Press `⌘R` to run. The first time you take a screenshot, the system will prompt for screen recording authorization as defined in `NSScreenCaptureUsageDescription`: **System Settings → Privacy & Security → Screen Recording**. Check `MoliShot` and then **fully quit and restart** the app to ensure it works correctly.

If you want the screenshot hotkeys to keep target menus, popovers, and tooltips open without closing them prematurely, you need to grant **Accessibility** permission. Screenshots will still work without it, but behaviors in these scenarios are best-effort.

### 5. Build DMG (For personal use)

The repository includes an automatic packaging script that generates `dist/MoliShot.dmg` and opens the output directory:

```bash
cd ~/Desktop/Shottr-Clone
./scripts/build-dmg.sh
```

The script automatically:

- Runs `xcodegen generate`
- Builds the `Release` configuration
- Locates the generated `MoliShot.app`
- Outputs `dist/MoliShot.dmg`
- Places `MoliShot.app` and an `Applications` shortcut in the DMG root, supporting drag-and-drop installation
- Opens the `dist/` directory

### Screen Recording Permission Prompting Repeatedly?

Do not call `CGRequestScreenCaptureAccess()` at startup. In **Debug / Unsigned** builds run from Xcode, `CGPreflightScreenCaptureAccess()` sometimes returns `false` indefinitely, prompting the system sheet on every launch. This behavior has been removed in the current version. If issues persist, ensure that the **specific path** of `MoliShot` currently checked in System Settings is correct (e.g. `DerivedData/.../Debug/MoliShot.app` vs `/Applications/MoliShot.app` are treated as separate entries by the system). For release versions, placing the app in `/Applications` with a consistent signature solves this.

### Xcodebuild Plugin Errors?

If `xcodebuild` in the terminal complains about failing to load `IDESimulatorFoundation`, that means Xcode's system components need initialization. Build the app using Xcode GUI once to fix this, or run:

```bash
sudo xcodebuild -runFirstLaunch
```

This is an issue with your local Xcode installation, not this project. Building via the Xcode GUI directly using `.xcodeproj` is unaffected.

## Usage

After launching, a camera icon will appear in the menu bar. Default hotkeys:

| Action | Hotkey |
| --- | --- |
| Area Screenshot | ⇧⌘1 |
| Capture Current Display | ⇧⌘3 |
| Scrolling Screenshot | ⇧⌘4 |
| Color Picker | ⇧⌘P |
| OCR Recognition Area | ⇧⌘R |

The editor window automatically pops up after a screenshot. Toolbar options from left to right: Pin/Copy → Tool Selection → Color/Stroke/Font Size/Opacity/Fill/Blur Radius (conditionally displayed based on selection) → Crop/Undo/Redo/Clear → Zoom → OCR/Save/Upload.

Editor Hotkeys:

| Action | Hotkey |
| --- | --- |
| Undo / Redo | `⌘Z` / `⌘⇧Z` |
| Copy Selected Annotation (copies full image if nothing selected) | `⌘C` |
| Paste Annotation | `⌘V` |
| Duplicate Annotation | `⌘D` |
| Delete Selected | `Delete` / `⌫` |
| Move selected Z-order (Up/Down/Front/Back) | `⌘]` / `⌘[` / `⌘⇧]` / `⌘⇧[` |
| Apply Crop / Cancel Crop | `Enter` / `Esc` |
| Zoom In / Zoom Out / Fit Window / Actual Size | `⌘+` `⌘-` / `⌘0` / `⌘1` |
| Save | `⌘S` |
| Deselect / Exit current interaction | `Esc` |

Single-key tool switching (automatically passed through during text editing):
`V` Select / `R` Rectangle / `O` Oval / `L` Line / `A` Arrow / `P` Pen / `T` Text / `N` Number (Counter) / `B` Blur / `X` Pixelate / `Y` Highlight.

Editor Additional Interactions:
- Changing color/stroke/font size/opacity/fill color/blur radius with an annotation selected updates it immediately and is undoable.
- Drag handles to resize selected annotations (drag endpoints for lines/arrows, resizing text scales the font size).
- Double-click text annotations to edit them.
- The status bar displays the current image size, annotation count, current tool, and zoom level.

## Project Structure

```
Sources/
├── App/                 # App entry point, menu bar, global coordination
├── Capture/             # ScreenCaptureKit, area selection, scrolling capture
├── Editor/              # Annotation editor, annotation types
├── OCR/                 # Vision text recognition
├── Pin/                 # Float/pinned window
├── ColorPicker/         # Color picker
├── Ruler/               # Ruler / Protractor
├── History/             # History storage and browsing
├── Hotkeys/             # Global hotkey management
├── Preferences/         # Preferences window
├── Services/            # Upload, export services
└── Utilities/           # Permissions, extensions, helper functions
Resources/
├── Info.plist
└── MoliShot.entitlements
project.yml              # XcodeGen configuration
```

## Known Limitations & Future Work

1. **Area screenshot only starts on the display where mouse is located**: This is by design, not a cross-display selection window.
2. **Scrolling screenshot still requires manual scrolling**: Stitching may fail if scrolling is too fast, overlaps are too small, or page elements jitter.
3. **OCR returns plain text only**: No text bounding boxes highlighted, segment copying, or structured search is supported yet.
4. **DMG Unsigned**: Manual bypassing is required for the first launch (see "Download & Installation"). We may support Developer ID signing & notarization later.
5. **No screen recording**: The current version only focuses on the screenshot workflow.
6. **Performance is not fully optimized**: Rendering cache is implemented for blur/pixelate, but canvas-level redrawing and zoom downsampling for the base image are not yet implemented. Dragging may stutter with 4K resolution and many annotations.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — Global hotkeys, the only third-party dependency, managed via SwiftPM.

## License

At your discretion, free to modify.
