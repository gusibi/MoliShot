import AppKit
import ScreenCaptureKit
import HotKey

enum RegionCaptureMode {
    case area
    case window
}

struct AreaCaptureResult {
    let image: NSImage
    let display: SCDisplay
    let sourceRect: CGRect
    let screenRect: CGRect
}

struct WindowCaptureTarget {
    let window: SCWindow
    let displayID: CGDirectDisplayID
    let hoverRect: CGRect
}

enum RegionSelectionResult {
    case area(AreaCaptureResult)
    case window(NSImage, WindowCaptureTarget)
}

/// Shows a fullscreen overlay window on every screen, lets the user either
/// drag a rect or click a window, and returns the captured result.
final class RegionSelectionController {

    private var overlayWindows: [RegionOverlayWindow] = []
    private var overlayBounds: CGRect = .zero
    private var windowRects: [WindowCandidate] = []
    private var targetDisplayID: CGDirectDisplayID?
    private weak var primarySelectionView: RegionSelectionView?
    /// SCShareableContent captured once during overlay startup and reused in `captureArea`,
    /// so the post-selection capture doesn't pay another ~500ms SCShareableContent tax.
    private var cachedContent: SCShareableContent?
    /// Pre-captured screen snapshots (keyed by display ID), taken BEFORE the overlay
    /// is shown. When the user selects a rect, we crop from this snapshot rather than
    /// calling ScreenCaptureKit again (which would capture the overlay dimming).
    private var screenSnapshots: [CGDirectDisplayID: NSImage] = [:]
    private let allowsWindowSelectionInAreaMode: Bool
    private let completion: (RegionSelectionResult?) -> Void
    private var mode: RegionCaptureMode = .area
    private var escapeHotkey: HotKey?
    private let captureEventTap = CaptureSessionEventTap()

    init(allowsWindowSelectionInAreaMode: Bool = true, completion: @escaping (RegionSelectionResult?) -> Void) {
        self.allowsWindowSelectionInAreaMode = allowsWindowSelectionInAreaMode
        self.completion = completion
    }

    func begin(mode: RegionCaptureMode) {
        self.mode = mode

        // Warn if secure input is active (password field focused) —
        // the system will black out that area in the screenshot.
        if Permissions.isSecureInputEnabled {
            let alert = NSAlert()
            alert.messageText = "Secure Input Active"
            alert.informativeText = "A password field or secure input is currently active. The captured area may appear black. Continue anyway?"
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
        }

        Task { @MainActor in
            prepareInitialOverlayState()
            // ① 先采集当前屏幕内容（覆盖层还没出现）
            do {
                try await self.captureScreenSnapshots()
            } catch {
                NSLog("Pre-capture screen snapshots failed: \(error)")
            }
            // ② 加载窗口信息
            do {
                try await self.loadOverlayContent()
            } catch {
                NSLog("Region begin failed: \(error)")
            }
            // ③ 再显示覆盖层（此时底层 UI 状态已被冻结在快照里）
            showOverlay()
        }
    }

    @MainActor
    private func prepareInitialOverlayState() {
        windowRects = []
        cachedContent = nil
        screenSnapshots = [:]
        targetDisplayID = nil

        if mode == .area,
           let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            overlayBounds = targetScreen.frame
            targetDisplayID = displayID(for: targetScreen)
        } else {
            overlayBounds = NSScreen.screens.desktopBounds
        }
    }

    /// Capture each display's full content BEFORE the overlay is shown.
    /// These snapshots are used later to crop the selected rect, avoiding
    /// the overlay's dimming being captured in the result.
    private func captureScreenSnapshots() async throws {
        let content = try await ScreenCaptureService.shared.shareableContent()
        cachedContent = content
        let displaysToCapture: [SCDisplay]
        if let targetDisplayID {
            displaysToCapture = content.displays.filter { $0.displayID == targetDisplayID }
        } else {
            displaysToCapture = content.displays
        }
        for display in displaysToCapture {
            let image = try await ScreenCaptureService.shared.captureDisplay(display)
            screenSnapshots[display.displayID] = image
        }
    }

    private func loadOverlayContent() async throws {
        // Reuse SCShareableContent cached by captureScreenSnapshots() if available.
        let content: SCShareableContent
        if let cached = cachedContent {
            content = cached
        } else {
            content = try await ScreenCaptureService.shared.shareableContent()
        }
        let areaTarget = await MainActor.run { () -> (CGRect, CGDirectDisplayID?)? in
            guard self.mode == .area else { return nil }
            let frame = self.overlayBounds
            let displayID = NSScreen.screens
                .first(where: { $0.frame == frame })
                .flatMap(self.displayID(for:))
            return (frame, displayID)
        }
        let bundleID = Bundle.main.bundleIdentifier
        let visibleWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier != bundleID &&
            $0.owningApplication?.applicationName != nil &&
            $0.windowLayer == 0 &&
            $0.frame.width > 40 && $0.frame.height > 40
        }

        // `SCShareableContent.windows` is not guaranteed to be in z-order, so ask
        // CGWindowList once for front-to-back order and sort our filtered windows by it.
        // Doing this once here keeps the 60Hz mouseMoved path free of the syscall while
        // still letting us resolve "which window is topmost under the cursor" correctly.
        let zOrder = frontToBackZOrder()
        let orderedWindows = visibleWindows.sorted { a, b in
            let za = zOrder[a.windowID] ?? Int.max
            let zb = zOrder[b.windowID] ?? Int.max
            return za < zb
        }

        await MainActor.run {
            self.cachedContent = content
            let orderedWindowRects = orderedWindows.map { self.windowCandidate(for: $0, displays: content.displays) }
            if let areaFrame = areaTarget?.0 {
                self.windowRects = orderedWindowRects.filter { $0.rect.intersects(areaFrame) }
            } else {
                self.windowRects = orderedWindowRects
            }
            self.applyOverlayUpdates()
        }
    }

    /// Maps each on-screen window's ID to its z-order index (0 = frontmost).
    /// Called once per capture session so mouseMoved doesn't have to repeat it.
    private func frontToBackZOrder() -> [CGWindowID: Int] {
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        var result: [CGWindowID: Int] = [:]
        result.reserveCapacity(infos.count)
        for (index, info) in infos.enumerated() {
            if let num = info[kCGWindowNumber as String] as? NSNumber {
                result[CGWindowID(num.uint32Value)] = index
            }
        }
        return result
    }

    @MainActor
    private func showOverlay() {
        if !overlayWindows.isEmpty {
            for window in overlayWindows {
                if let view = window.contentView as? RegionSelectionView {
                    view.updateWindowRects(windowRects)
                }
            }
            return
        }

        // Register a temporary global hotkey for Escape to cancel selection without needing app activation.
        // This avoids dismissing menus of other applications.
        escapeHotkey = HotKey(key: .escape, modifiers: [])
        escapeHotkey?.keyDownHandler = { [weak self] in
            self?.handleResult(.cancelled)
        }

        // Create one overlay panel per screen.
        // The primary panel (on the screen containing the mouse) handles selection;
        // secondary panels just show the dim overlay for visual consistency.
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let desktopBounds = NSScreen.screens.desktopBounds

        for screen in screens {
            let frame = screen.frame
            let panel = RegionOverlayWindow(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.configure()

            let isPrimary = frame.contains(mouseLocation)
            let screenDisplayID = displayID(for: screen)
            let view = RegionSelectionView(
                frame: NSRect(origin: .zero, size: frame.size),
                desktopBounds: isPrimary ? overlayBounds : desktopBounds,
                mode: isPrimary ? mode : .area,
                allowsWindowSelectionInAreaMode: isPrimary ? allowsWindowSelectionInAreaMode : false,
                windowRects: windowRects,
                snapshotImage: isPrimary ? screenDisplayID.flatMap { screenSnapshots[$0] } : nil,
                displayScale: screenDisplayID.flatMap(displayScale(for:)) ?? screen.backingScaleFactor
            )

            if isPrimary {
                // Only the primary panel reports selection results.
                primarySelectionView = view
                view.onResult = { [weak panel] r in panel?.selectionCompletion?(r) }
                panel.selectionCompletion = { [weak self] result in
                    self?.handleResult(result)
                }
            }

            panel.contentView = view
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            overlayWindows.append(panel)
        }

        if Permissions.hasAccessibilityPermission {
            primarySelectionView?.beginPointerPreservationSession()
            _ = captureEventTap.start { [weak self] event in
                self?.primarySelectionView?.handleInterceptedEvent(event)
            }
        }

    }

    @MainActor
    private func applyOverlayUpdates() {
        for window in overlayWindows {
            if let view = window.contentView as? RegionSelectionView {
                view.updateWindowRects(windowRects)
            }
        }
    }

    private func handleResult(_ result: RegionOverlayWindow.Result) {
        Task { @MainActor in
            let content = self.cachedContent
            let snapshots = self.screenSnapshots
            self.dismiss()
            await Task.yield()

            switch result {
            case .cancelled:
                completion(nil)
            case .area(let rect):
                await self.captureArea(rect, cachedContent: content, screenSnapshots: snapshots)
            case .window(let target):
                await self.captureWindow(target)
            }
        }
    }

    @MainActor
    private func captureArea(
        _ rect: NSRect,
        cachedContent: SCShareableContent?,
        screenSnapshots: [CGDirectDisplayID: NSImage]
    ) async {
        do {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }) else {
                completion(nil)
                return
            }
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            guard let content = cachedContent,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                completion(nil)
                return
            }

            // Selection rects use AppKit screen coordinates (origin at bottom-left).
            // ScreenCaptureKit sourceRect uses display-local logical coordinates
            // with the Y axis measured down from the display's top edge.
            let screenFrame = screen.frame
            let localX = rect.origin.x - screenFrame.origin.x
            let localY = screenFrame.height - (rect.origin.y - screenFrame.origin.y) - rect.height
            let source = CGRect(
                x: localX,
                y: localY,
                width: rect.width,
                height: rect.height
            )

            // Prefer cropping from the pre-captured snapshot (taken before overlay was shown)
            // so the result doesn't include the overlay's dimming effect.
            if let snapshot = screenSnapshots[displayID], let cgImage = snapshot.cgImageRef {
                let scale = CGFloat(cgImage.width) / snapshot.size.width
                let pixelRect = CGRect(
                    x: source.origin.x * scale,
                    y: source.origin.y * scale,
                    width: source.width * scale,
                    height: source.height * scale
                )
                if let cropped = cgImage.cropping(to: pixelRect) {
                    let image = NSImage(cgImage: cropped, size: rect.size)
                    completion(.area(AreaCaptureResult(image: image, display: display, sourceRect: source, screenRect: rect)))
                    return
                }
            }

            // Fallback: if pre-capture snapshot is unavailable, capture via ScreenCaptureKit
            // excluding our own overlay windows.
            let ownWindows: [SCWindow]
            if overlayWindows.isEmpty {
                ownWindows = []
            } else {
                ownWindows = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
                }
            }
            let image = try await ScreenCaptureService.shared.captureRect(source, onDisplay: display, excludingWindows: ownWindows)
            completion(.area(AreaCaptureResult(image: image, display: display, sourceRect: source, screenRect: rect)))
        } catch {
            NSLog("Capture area failed: \(error)")
            completion(nil)
        }
    }

    @MainActor
    private func captureWindow(_ target: WindowCaptureTarget) async {
        do {
            let image = try await ScreenCaptureService.shared.captureWindow(target.window, onDisplayID: target.displayID)
            completion(.window(image, target))
        } catch {
            NSLog("Capture window failed: \(error)")
            completion(nil)
        }
    }

    private func dismiss() {
        captureEventTap.stop()
        primarySelectionView?.endPointerPreservationSession()
        escapeHotkey = nil
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows = []
        primarySelectionView = nil
        windowRects = []
        cachedContent = nil
        screenSnapshots = [:]
        targetDisplayID = nil
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func displayScale(for displayID: CGDirectDisplayID) -> CGFloat? {
        NSScreen.screens
            .first(where: { self.displayID(for: $0) == displayID })?
            .backingScaleFactor
    }

    private func appKitRect(fromScreenCaptureRect rect: CGRect, displays: [SCDisplay]) -> CGRect {
        let matchedDisplay = displays
            .map { ($0, intersectionArea($0.frame, rect)) }
            .max { $0.1 < $1.1 }
        guard
            let display = matchedDisplay?.0,
            (matchedDisplay?.1 ?? 0) > 0,
            let screen = screen(for: display)
        else {
            let desktopBounds = NSScreen.screens.desktopBounds
            return CGRect(
                x: rect.origin.x,
                y: desktopBounds.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
        let localX = rect.origin.x - display.frame.origin.x
        let localTopY = rect.origin.y - display.frame.origin.y
        return CGRect(
            x: screen.frame.origin.x + localX,
            y: screen.frame.maxY - localTopY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func screen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first { self.displayID(for: $0) == display.displayID }
    }

    private func windowCandidate(for window: SCWindow, displays: [SCDisplay]) -> WindowCandidate {
        let matchedDisplay = displays
            .map { ($0, intersectionArea($0.frame, window.frame)) }
            .max { $0.1 < $1.1 }
        let fallbackDisplayID = matchedDisplay?.0.displayID ?? CGMainDisplayID()
        return WindowCandidate(
            window: window,
            rect: appKitRect(fromScreenCaptureRect: window.frame, displays: displays),
            displayID: fallbackDisplayID
        )
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

/// Fullscreen borderless transparent panel that hosts the selection view.
///
/// We use NSPanel with nonActivatingPanel so the overlay never steals focus
/// from the foreground app (which would dismiss its menus). Callers use the
/// inherited `NSPanel.init(contentRect:styleMask:backing:defer:screen:)`
/// and then call `configure()`.
final class RegionOverlayWindow: NSPanel {
    enum Result {
        case area(NSRect)
        case window(WindowCaptureTarget)
        case cancelled
    }
    var selectionCompletion: ((Result) -> Void)?

    func configure() {
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        // 使用屏蔽窗口级别，确保在所有菜单和 UI 之上
        self.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false
        // 不激活 app、不成为 key/main window
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // 覆盖层本身不出现在截图结果里
        self.sharingType = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct WindowCandidate {
    let window: SCWindow
    let rect: CGRect
    let displayID: CGDirectDisplayID
}
