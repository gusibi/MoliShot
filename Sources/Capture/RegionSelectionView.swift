import AppKit
import CoreGraphics
import ScreenCaptureKit

/// The NSView that draws the dim overlay, selection rect, magnifier, and handles mouse.
final class RegionSelectionView: NSView {
    var onResult: ((RegionOverlayWindow.Result) -> Void)?

    private let desktopBounds: CGRect
    private let mode: RegionCaptureMode
    private let allowsWindowSelectionInAreaMode: Bool
    private let snapshotImage: NSImage?
    private let displayScale: CGFloat
    private var windowRects: [WindowCandidate]

    private var dragStart: NSPoint?
    private var lastDragPoint: NSPoint?
    private var currentRect: NSRect?
    private var hoveredWindow: WindowCandidate?
    private var mouseLocation: NSPoint = .zero
    private var didDragSelection = false
    private var isMovingSelection = false
    private var isSpaceHeld = false
    private var hasPushedCrosshair = false
    private var isPointerPreservationActive = false
    private var didHideCursor = false

    private var trackingArea: NSTrackingArea?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?

    private static let sizeLabelAttributes: [NSAttributedString.Key: Any] = [
        .font: RegionSelectionView.safeMonospacedFont(size: 12, weight: .medium),
        .foregroundColor: NSColor.white
    ]
    private static let magnifierLabelAttributes: [NSAttributedString.Key: Any] = [
        .font: RegionSelectionView.safeMonospacedFont(size: 11, weight: .regular),
        .foregroundColor: NSColor.white
    ]

    private static func safeMonospacedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let menlo = NSFont(name: "Menlo", size: size) {
            return menlo
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    init(
        frame: NSRect,
        desktopBounds: CGRect,
        mode: RegionCaptureMode,
        allowsWindowSelectionInAreaMode: Bool,
        windowRects: [WindowCandidate],
        snapshotImage: NSImage? = nil,
        displayScale: CGFloat = 1
    ) {
        self.desktopBounds = desktopBounds
        self.mode = mode
        self.allowsWindowSelectionInAreaMode = allowsWindowSelectionInAreaMode
        self.windowRects = windowRects
        self.snapshotImage = snapshotImage
        self.displayScale = max(displayScale, 1)
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateWindowRects(_ windowRects: [WindowCandidate]) {
        self.windowRects = windowRects
        syncHoverToMouseLocation()
    }

    func beginPointerPreservationSession() {
        guard !isPointerPreservationActive else { return }
        isPointerPreservationActive = CGAssociateMouseAndMouseCursorPosition(0) == .success
        guard isPointerPreservationActive else { return }
        NSCursor.hide()
        didHideCursor = true
    }

    func endPointerPreservationSession() {
        guard isPointerPreservationActive || didHideCursor else { return }
        if isPointerPreservationActive {
            _ = CGAssociateMouseAndMouseCursorPosition(1)
        }
        isPointerPreservationActive = false
        if didHideCursor {
            NSCursor.unhide()
            didHideCursor = false
        }
    }

    func handleInterceptedEvent(_ event: CaptureSessionEventTap.Event) {
        let localPoint = pointForInterceptedEvent(event)
        let isInsideInteractiveBounds = bounds.contains(localPoint)

        if !isInsideInteractiveBounds {
            if event.type == .mouseMoved {
                mouseLocation = localPoint
                hoveredWindow = nil
                needsDisplay = true
            }
            return
        }

        switch event.type {
        case .mouseMoved:
            handleMouseMoved(at: localPoint)
        case .leftMouseDown:
            handlePrimaryMouseDown(at: localPoint)
        case .leftMouseDragged:
            handlePrimaryMouseDragged(at: localPoint, modifiers: event.modifiers)
        case .leftMouseUp:
            handlePrimaryMouseUp(at: localPoint)
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp,
             .otherMouseDown, .otherMouseDragged, .otherMouseUp,
             .scrollWheel:
            swallowSecondaryPointerEvent(at: localPoint)
        case .flagsChanged:
            needsDisplay = true
        default:
            break
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseEntered(with event: NSEvent) {}
    override func mouseExited(with event: NSEvent) {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingArea()
        if window != nil {
            pushCrosshairIfNeeded()
            installKeyMonitorsIfNeeded()
            syncHoverToMouseLocation()
        } else {
            endPointerPreservationSession()
            removeKeyMonitors()
            popCrosshairIfNeeded()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let highlight = activeHighlightRect()
        drawMask(excluding: highlight, in: ctx)

        if let highlight {
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(highlight)
            drawSizeLabel(for: highlight, in: ctx)
        }

        drawCrosshair(at: mouseLocation, in: ctx)
        drawMagnifier(at: mouseLocation, in: ctx)
    }

    private func activeHighlightRect() -> NSRect? {
        if let currentRect {
            return currentRect
        }
        guard let hoveredWindow else { return nil }
        return convertGlobalRectToLocal(hoveredWindow.rect)
    }

    private func drawMask(excluding highlight: NSRect?, in ctx: CGContext) {
        ctx.clear(bounds)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)

        guard let highlight, highlight.width > 0, highlight.height > 0 else {
            ctx.fill(bounds)
            return
        }

        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(highlight)
        ctx.addPath(path)
        ctx.drawPath(using: .eoFill)
    }

    private func drawSizeLabel(for rect: NSRect, in ctx: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }

        let pointText = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded())) pt"
        let pixelText = "\(Int((rect.width * displayScale).rounded())) × \(Int((rect.height * displayScale).rounded())) px"
        let text = "\(pointText)\n\(pixelText)" as NSString
        let attrs = Self.sizeLabelAttributes
        let size = text.boundingRect(
            with: NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs
        ).size
        let padding = CGSize(width: 8, height: 6)
        let labelSize = NSSize(width: ceil(size.width + padding.width * 2), height: ceil(size.height + padding.height * 2))
        var origin = NSPoint(x: rect.maxX - labelSize.width, y: rect.minY - labelSize.height - 6)
        if origin.y < 4 { origin.y = rect.maxY + 6 }
        if origin.x < 4 { origin.x = rect.minX }
        if origin.x + labelSize.width > bounds.maxX - 4 {
            origin.x = bounds.maxX - labelSize.width - 4
        }

        let labelRect = NSRect(origin: origin, size: labelSize)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
        ctx.fill(labelRect)
        text.draw(
            in: labelRect.insetBy(dx: padding.width, dy: padding.height / 2),
            withAttributes: attrs
        )
    }

    private func drawCrosshair(at point: NSPoint, in ctx: CGContext) {
        guard mode == .area else { return }
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: point.x - 8, y: point.y))
        ctx.addLine(to: CGPoint(x: point.x + 8, y: point.y))
        ctx.move(to: CGPoint(x: point.x, y: point.y - 8))
        ctx.addLine(to: CGPoint(x: point.x, y: point.y + 8))
        ctx.strokePath()
    }

    private func drawMagnifier(at point: NSPoint, in ctx: CGContext) {
        guard mode == .area, let snapshotImage else { return }

        let magnifierSize = NSSize(width: 140, height: 140)
        var origin = NSPoint(x: point.x + 18, y: point.y + 18)
        if origin.x + magnifierSize.width > bounds.maxX - 8 {
            origin.x = point.x - magnifierSize.width - 18
        }
        if origin.y + magnifierSize.height > bounds.maxY - 8 {
            origin.y = point.y - magnifierSize.height - 18
        }
        if origin.x < 8 { origin.x = 8 }
        if origin.y < 8 { origin.y = 8 }
        let magnifierRect = NSRect(origin: origin, size: magnifierSize)

        let sampleSize: CGFloat = 18
        let sourceRect = NSRect(
            x: max(0, min(point.x - sampleSize / 2, snapshotImage.size.width - sampleSize)),
            y: max(0, min(point.y - sampleSize / 2, snapshotImage.size.height - sampleSize)),
            width: sampleSize,
            height: sampleSize
        )

        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.82).cgColor)
        ctx.fill(magnifierRect)
        snapshotImage.draw(
            in: magnifierRect.insetBy(dx: 6, dy: 24),
            from: sourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(magnifierRect)

        let crossRect = magnifierRect.insetBy(dx: 6, dy: 24)
        let midX = crossRect.midX
        let midY = crossRect.midY
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: midX - 10, y: midY))
        ctx.addLine(to: CGPoint(x: midX + 10, y: midY))
        ctx.move(to: CGPoint(x: midX, y: midY - 10))
        ctx.addLine(to: CGPoint(x: midX, y: midY + 10))
        ctx.strokePath()

        let globalPoint = NSPoint(x: point.x + desktopBounds.origin.x, y: point.y + desktopBounds.origin.y)
        let info = "\(Int(globalPoint.x.rounded())), \(Int(globalPoint.y.rounded()))" as NSString
        info.draw(
            at: NSPoint(x: magnifierRect.minX + 8, y: magnifierRect.maxY - 18),
            withAttributes: Self.magnifierLabelAttributes
        )
        ctx.restoreGState()
    }

    private func convertGlobalRectToLocal(_ rect: CGRect) -> NSRect {
        NSRect(
            x: rect.origin.x - desktopBounds.origin.x,
            y: rect.origin.y - desktopBounds.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    private func pointForInterceptedEvent(_ event: CaptureSessionEventTap.Event) -> NSPoint {
        if isPointerPreservationActive {
            return clampedLocalPoint(NSPoint(
                x: mouseLocation.x + event.deltaX,
                y: mouseLocation.y - event.deltaY
            ))
        }
        return localPoint(fromInterceptedGlobalLocation: event.location)
    }

    private func clampedLocalPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func localPoint(fromInterceptedGlobalLocation location: CGPoint) -> NSPoint {
        let desktop = NSScreen.screens.desktopBounds
        let appKitGlobal = NSPoint(
            x: location.x,
            y: desktop.maxY - location.y
        )
        return NSPoint(
            x: appKitGlobal.x - desktopBounds.origin.x,
            y: appKitGlobal.y - desktopBounds.origin.y
        )
    }

    override func mouseDown(with event: NSEvent) {
        handlePrimaryMouseDown(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        handlePrimaryMouseDragged(at: event.locationInWindow, modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }

    override func mouseUp(with event: NSEvent) {
        handlePrimaryMouseUp(at: event.locationInWindow)
    }

    override func rightMouseDown(with event: NSEvent) {
        swallowSecondaryPointerEvent(at: event.locationInWindow)
    }

    override func rightMouseDragged(with event: NSEvent) {
        swallowSecondaryPointerEvent(at: event.locationInWindow)
    }

    override func rightMouseUp(with event: NSEvent) {
        swallowSecondaryPointerEvent(at: event.locationInWindow)
    }

    override func otherMouseDown(with event: NSEvent) {
        swallowSecondaryPointerEvent(at: event.locationInWindow)
    }

    override func otherMouseDragged(with event: NSEvent) {
        swallowSecondaryPointerEvent(at: event.locationInWindow)
    }

    override func otherMouseUp(with event: NSEvent) {
        swallowSecondaryPointerEvent(at: event.locationInWindow)
    }

    override func scrollWheel(with event: NSEvent) {
        swallowSecondaryPointerEvent(at: event.locationInWindow)
    }

    override func cursorUpdate(with event: NSEvent) {
        applyOverlayCursor()
        updateHoveredWindow(at: event.locationInWindow)
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        updateSpaceState(with: event, isPressed: true)
    }

    override func keyUp(with event: NSEvent) {
        updateSpaceState(with: event, isPressed: false)
    }

    private func handlePrimaryMouseDown(at location: NSPoint) {
        dragStart = location
        lastDragPoint = location
        mouseLocation = location
        didDragSelection = false
        isMovingSelection = false
        applyOverlayCursor()
        updateHoveredWindow(at: location)

        if mode == .area, allowsWindowSelectionInAreaMode, let hoveredWindow {
            currentRect = convertGlobalRectToLocal(hoveredWindow.rect)
        } else {
            currentRect = .zero
        }
        needsDisplay = true
    }

    private func handlePrimaryMouseDragged(at location: NSPoint, modifiers: NSEvent.ModifierFlags) {
        guard mode == .area, let start = dragStart else { return }
        let current = location
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        mouseLocation = current
        applyOverlayCursor()
        updateHoveredWindow(at: current)

        if !didDragSelection {
            didDragSelection = hypot(current.x - start.x, current.y - start.y) > 2
        }

        if isSpaceHeld, didDragSelection, let currentRect, let lastDragPoint {
            isMovingSelection = true
            self.currentRect = currentRect.offsetBy(dx: current.x - lastDragPoint.x, dy: current.y - lastDragPoint.y)
            self.lastDragPoint = current
            needsDisplay = true
            return
        }

        isMovingSelection = false
        currentRect = selectionRect(from: start, to: current, flags: flags)
        lastDragPoint = current
        needsDisplay = true
    }

    private func handlePrimaryMouseUp(at location: NSPoint) {
        defer {
            dragStart = nil
            lastDragPoint = nil
            isMovingSelection = false
        }

        mouseLocation = location
        applyOverlayCursor()
        updateHoveredWindow(at: location)

        if mode == .area {
            if allowsWindowSelectionInAreaMode, !didDragSelection, let hoveredWindow {
                let cursorDisplayID = displayID(forGlobalPoint: NSPoint(
                    x: location.x + desktopBounds.origin.x,
                    y: location.y + desktopBounds.origin.y
                )) ?? hoveredWindow.displayID
                onResult?(.window(WindowCaptureTarget(
                    window: hoveredWindow.window,
                    displayID: cursorDisplayID,
                    hoverRect: hoveredWindow.rect
                )))
                return
            }

            guard let currentRect, currentRect.width > 2, currentRect.height > 2 else {
                onResult?(.cancelled)
                return
            }
            let screenRect = NSRect(
                x: currentRect.origin.x + desktopBounds.origin.x,
                y: currentRect.origin.y + desktopBounds.origin.y,
                width: currentRect.width,
                height: currentRect.height
            )
            onResult?(.area(screenRect))
        } else if let hoveredWindow {
            onResult?(.window(WindowCaptureTarget(
                window: hoveredWindow.window,
                displayID: hoveredWindow.displayID,
                hoverRect: hoveredWindow.rect
            )))
        } else {
            onResult?(.cancelled)
        }
    }

    private func selectionRect(from start: NSPoint, to current: NSPoint, flags: NSEvent.ModifierFlags) -> NSRect {
        var dx = current.x - start.x
        var dy = current.y - start.y
        var width = abs(dx)
        var height = abs(dy)

        if flags.contains(.shift) {
            let side = max(width, height)
            width = side
            height = side
            dx = dx >= 0 ? side : -side
            dy = dy >= 0 ? side : -side
        }

        if flags.contains(.option) {
            return NSRect(
                x: start.x - width,
                y: start.y - height,
                width: width * 2,
                height: height * 2
            )
        }

        return NSRect(
            x: min(start.x, start.x + dx),
            y: min(start.y, start.y + dy),
            width: width,
            height: height
        )
    }

    override func mouseMoved(with event: NSEvent) {
        handleMouseMoved(at: event.locationInWindow)
    }

    private func handleMouseMoved(at location: NSPoint) {
        applyOverlayCursor()
        mouseLocation = location
        if mode == .window || mode == .area {
            updateHoveredWindow(at: location)
        }
        needsDisplay = true
    }

    private func swallowSecondaryPointerEvent(at location: NSPoint) {
        mouseLocation = location
        applyOverlayCursor()
        updateHoveredWindow(at: location)
        needsDisplay = true
    }

    private func updateHoveredWindow(at local: NSPoint) {
        let globalPoint = NSPoint(
            x: local.x + desktopBounds.origin.x,
            y: local.y + desktopBounds.origin.y
        )

        for candidate in windowRects where candidate.rect.contains(globalPoint) {
            hoveredWindow = candidate
            return
        }
        hoveredWindow = nil
    }

    private func syncHoverToMouseLocation() {
        let global = NSEvent.mouseLocation
        mouseLocation = NSPoint(
            x: global.x - desktopBounds.origin.x,
            y: global.y - desktopBounds.origin.y
        )
        updateHoveredWindow(at: mouseLocation)
        needsDisplay = true
    }

    private func displayID(forGlobalPoint point: NSPoint) -> CGDirectDisplayID? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func applyOverlayCursor() {
        pushCrosshairIfNeeded()
        NSCursor.crosshair.set()
    }

    private func pushCrosshairIfNeeded() {
        guard !hasPushedCrosshair else { return }
        NSCursor.crosshair.push()
        hasPushedCrosshair = true
    }

    private func popCrosshairIfNeeded() {
        guard hasPushedCrosshair else { return }
        NSCursor.pop()
        hasPushedCrosshair = false
    }

    private func installKeyMonitorsIfNeeded() {
        guard globalKeyDownMonitor == nil, globalKeyUpMonitor == nil else { return }
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.updateSpaceState(with: event, isPressed: true)
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.updateSpaceState(with: event, isPressed: false)
        }
    }

    private func removeKeyMonitors() {
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
        }
        if let globalKeyUpMonitor {
            NSEvent.removeMonitor(globalKeyUpMonitor)
        }
        globalKeyDownMonitor = nil
        globalKeyUpMonitor = nil
        isSpaceHeld = false
    }

    private func updateSpaceState(with event: NSEvent, isPressed: Bool) {
        guard event.keyCode == 49 else { return }
        isSpaceHeld = isPressed
        needsDisplay = true
    }
}
