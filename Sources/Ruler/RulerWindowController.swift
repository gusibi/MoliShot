import AppKit

/// Multi-screen on-screen ruler / protractor. Drag anywhere to measure pixel
/// distance, angle, and horizontal / vertical deltas across all displays.
final class RulerWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var overlayWindows: [RulerOverlayWindow] = []
    private var overlayViews: [RulerOverlayView] = []
    private var isClosing = false

    private var startPoint: NSPoint?
    private var endPoint: NSPoint?

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        if overlayWindows.isEmpty {
            buildOverlays()
        }

        overlayWindows.forEach { $0.orderFrontRegardless() }
        overlayWindows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
        overlayViews.removeAll()
        onClose()
        isClosing = false
    }

    private func buildOverlays() {
        for screen in NSScreen.screens {
            let window = RulerOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.delegate = self
            window.configure()

            let view = RulerOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
            view.onDismiss = { [weak self] in self?.close() }
            view.onMeasureStart = { [weak self] point in self?.beginMeasurement(at: point) }
            view.onMeasureChange = { [weak self] point in self?.updateMeasurement(to: point) }
            view.onMeasureEnd = { [weak self] point in self?.finishMeasurement(at: point) }

            window.contentView = view
            overlayWindows.append(window)
            overlayViews.append(view)
        }
    }

    private func beginMeasurement(at point: NSPoint) {
        startPoint = point
        endPoint = point
        refreshViews()
    }

    private func updateMeasurement(to point: NSPoint) {
        endPoint = point
        refreshViews()
    }

    private func finishMeasurement(at point: NSPoint) {
        endPoint = point
        refreshViews()
    }

    private func refreshViews() {
        overlayViews.forEach { view in
            view.measurementStart = startPoint
            view.measurementEnd = endPoint
            view.needsDisplay = true
        }
    }

    func windowWillClose(_ notification: Notification) {
        if !isClosing, overlayWindows.contains(where: { $0 == notification.object as? NSWindow }) {
            close()
        }
    }
}

private final class RulerOverlayWindow: NSWindow {
    func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RulerOverlayView: NSView {
    var onDismiss: (() -> Void)?
    var onMeasureStart: ((NSPoint) -> Void)?
    var onMeasureChange: ((NSPoint) -> Void)?
    var onMeasureEnd: ((NSPoint) -> Void)?

    var measurementStart: NSPoint?
    var measurementEnd: NSPoint?

    private let screenFrame: NSRect

    init(frame frameRect: NSRect, screenFrame: NSRect) {
        self.screenFrame = screenFrame
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.04).cgColor)
        ctx.fill(bounds)

        guard let start = measurementStart, let end = measurementEnd else {
            drawHint(in: ctx)
            return
        }

        let localStart = localPoint(fromGlobal: start)
        let localEnd = localPoint(fromGlobal: end)

        drawMeasurementLine(from: localStart, to: localEnd, in: ctx)
        drawInfoPanel(for: start, end: end, localEnd: localEnd, in: ctx)
    }

    override func mouseDown(with event: NSEvent) {
        onMeasureStart?(globalPoint(from: convert(event.locationInWindow, from: nil)))
    }

    override func mouseDragged(with event: NSEvent) {
        onMeasureChange?(globalPoint(from: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        onMeasureEnd?(globalPoint(from: convert(event.locationInWindow, from: nil)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
        }
    }

    private func drawMeasurementLine(from start: NSPoint, to end: NSPoint, in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.systemYellow.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        let ticks = 10
        let dx = (end.x - start.x) / CGFloat(ticks)
        let dy = (end.y - start.y) / CGFloat(ticks)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let nx = -sin(angle)
        let ny = cos(angle)

        for i in 0...ticks {
            let tx = start.x + dx * CGFloat(i)
            let ty = start.y + dy * CGFloat(i)
            let tickLength: CGFloat = i % 5 == 0 ? 8 : 4
            ctx.move(to: CGPoint(x: tx - nx * tickLength, y: ty - ny * tickLength))
            ctx.addLine(to: CGPoint(x: tx + nx * tickLength, y: ty + ny * tickLength))
        }
        ctx.strokePath()

        ctx.setStrokeColor(NSColor.systemOrange.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: start.x, y: end.y))
        ctx.addLine(to: end)
        ctx.move(to: start)
        ctx.addLine(to: CGPoint(x: end.x, y: start.y))
        ctx.strokePath()
    }

    private func drawInfoPanel(for start: NSPoint, end: NSPoint, localEnd: NSPoint, in ctx: CGContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let degrees = atan2(dy, dx) * 180 / .pi
        let info = String(
            format: "d %.1f px   dx %.1f   dy %.1f   theta %.1f deg",
            distance, dx, dy, degrees
        )

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: info, attributes: attrs)
        let textSize = text.size()
        let panelSize = NSSize(width: textSize.width + 16, height: textSize.height + 10)
        let origin = clampedPanelOrigin(near: localEnd, size: panelSize)
        let panel = NSRect(origin: origin, size: panelSize)

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
        ctx.fill(panel)
        text.draw(at: NSPoint(x: panel.origin.x + 8, y: panel.origin.y + 5))
    }

    private func drawHint(in ctx: CGContext) {
        let hint = L10n.text(.rulerHint)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: hint, attributes: attrs)
        let size = text.size()
        let bg = NSRect(
            x: bounds.midX - size.width / 2 - 12,
            y: bounds.maxY - 60,
            width: size.width + 24,
            height: size.height + 12
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.fill(bg)
        text.draw(at: NSPoint(x: bg.origin.x + 12, y: bg.origin.y + 6))
    }

    private func localPoint(fromGlobal point: NSPoint) -> NSPoint {
        NSPoint(x: point.x - screenFrame.origin.x, y: point.y - screenFrame.origin.y)
    }

    private func globalPoint(from local: NSPoint) -> NSPoint {
        NSPoint(x: local.x + screenFrame.origin.x, y: local.y + screenFrame.origin.y)
    }

    private func clampedPanelOrigin(near point: NSPoint, size: NSSize) -> NSPoint {
        let proposed = NSPoint(x: point.x + 12, y: point.y + 12)
        let maxX = max(8, bounds.width - size.width - 8)
        let maxY = max(8, bounds.height - size.height - 8)
        return NSPoint(
            x: min(max(8, proposed.x), maxX),
            y: min(max(8, proposed.y), maxY)
        )
    }
}
