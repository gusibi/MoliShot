import AppKit

/// Floating borderless window pinned above all others, draggable by the image,
/// shows a small toolbar on hover with copy / save / close.
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private let image: NSImage
    private let onClose: (PinWindowController) -> Void

    init(image: NSImage, origin: NSPoint?, onClose: @escaping (PinWindowController) -> Void) {
        self.image = image
        self.onClose = onClose

        let size = PinWindowController.fitSize(for: image.size)
        let point = origin ?? NSPoint(
            x: (NSScreen.main?.frame.midX ?? 600) - size.width / 2,
            y: (NSScreen.main?.frame.midY ?? 400) - size.height / 2
        )
        let window = PinWindow(
            contentRect: NSRect(origin: point, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.configure()
        super.init(window: window)
        window.delegate = self

        let view = PinView(frame: NSRect(origin: .zero, size: size), image: image)
        view.onClose = { [weak self] in
            self?.close()
        }
        view.onCopy = { [weak self] in
            guard let self = self else { return }
            NSPasteboard.general.writeImage(self.image)
        }
        view.onSave = { [weak self] in self?.save() }
        view.onOCR = { [weak self] in
            guard let self = self else { return }
            OCRService.shared.recognize(in: self.image) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        AppCoordinator.shared.showOCRResult(text)
                    case .failure(let error):
                        AppCoordinator.shared.presentAlert(title: L10n.text(.ocr), message: error.localizedDescription)
                    }
                }
            }
        }
        window.contentView = view
        window.alphaValue = 0  // shown via the pop-in animation in showWindow
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pop in with a short rise + fade so the pin reads as arriving from the
    /// capture, instead of appearing out of nowhere.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window, window.alphaValue == 0 else { return }
        if MoliDesign.reduceMotion {
            window.alphaValue = 1
            return
        }
        let finalFrame = window.frame
        window.setFrame(finalFrame.offsetBy(dx: 0, dy: -10), display: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        }
    }

    /// Mirror the entrance: fade out along the same path before closing.
    override func close() {
        guard let window, window.alphaValue > 0, !MoliDesign.reduceMotion else {
            super.close()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 0
            window.animator().setFrame(window.frame.offsetBy(dx: 0, dy: -8), display: true)
        }, completionHandler: {
            super.close()
        })
    }

    private static func fitSize(for s: NSSize) -> NSSize {
        let maxSide: CGFloat = 900
        var w = s.width, h = s.height
        if w > maxSide { h *= maxSide / w; w = maxSide }
        if h > maxSide { w *= maxSide / h; h = maxSide }
        return NSSize(width: max(80, w), height: max(80, h))
    }

    private func save() {
        _ = try? AppSettings.save(image: image, prefix: "Pin")
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}

final class PinWindow: NSWindow {
    func configure() {
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { true }
}

final class PinView: NSView {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onOCR: (() -> Void)?

    private let imageView: DraggablePinImageView
    private let toolbarChrome: NSVisualEffectView

    init(frame: NSRect, image: NSImage) {
        self.imageView = DraggablePinImageView(frame: frame)
        self.imageView.image = image
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.autoresizingMask = [.width, .height]

        // Hover toolbar rendered on a translucent HUD material so it reads as
        // floating chrome rather than an opaque strip.
        self.toolbarChrome = NSVisualEffectView()
        toolbarChrome.material = .hudWindow
        toolbarChrome.blendingMode = .withinWindow
        toolbarChrome.state = .active
        toolbarChrome.wantsLayer = true
        toolbarChrome.layer?.cornerRadius = 8
        toolbarChrome.layer?.masksToBounds = true
        toolbarChrome.translatesAutoresizingMaskIntoConstraints = false
        toolbarChrome.alphaValue = 0

        super.init(frame: frame)
        wantsLayer = true
        applyStyle()

        addSubview(imageView)
        addSubview(toolbarChrome)

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 4
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbarChrome.addSubview(toolbar)

        let closeBtn = makeBtn("xmark.circle.fill", tooltip: L10n.text(.close), sel: #selector(closeTap))
        let copyBtn = makeBtn("doc.on.doc", tooltip: L10n.text(.copy), sel: #selector(copyTap))
        let saveBtn = makeBtn("arrow.down.circle", tooltip: L10n.text(.save), sel: #selector(saveTap))
        let ocrBtn = makeBtn("textformat", tooltip: L10n.text(.ocr), sel: #selector(ocrTap))
        [closeBtn, copyBtn, saveBtn, ocrBtn].forEach { toolbar.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: toolbarChrome.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: toolbarChrome.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: toolbarChrome.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: toolbarChrome.bottomAnchor),
            toolbarChrome.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            toolbarChrome.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])

        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    private func applyStyle() {
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = MoliDesign.hairline.cgColor
        layer?.masksToBounds = true
    }

    private func makeBtn(_ symbol: String, tooltip: String, sel: Selector) -> NSButton {
        let b = MoliHoverButton()
        b.layer?.cornerRadius = 5
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        b.toolTip = tooltip
        b.setAccessibilityLabel(tooltip)
        b.target = self
        b.action = sel
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = MoliDesign.reduceMotion ? 0.01 : 0.15
            toolbarChrome.animator().alphaValue = 1
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = MoliDesign.reduceMotion ? 0.01 : 0.2
            toolbarChrome.animator().alphaValue = 0
        }
    }

    @objc private func closeTap() { onClose?() }
    @objc private func copyTap() { onCopy?() }
    @objc private func saveTap() { onSave?() }
    @objc private func ocrTap() { onOCR?() }
}

private final class DraggablePinImageView: NSImageView {
    private var dragStartScreenPoint: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    override func mouseDown(with event: NSEvent) {
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartScreenPoint, let startOrigin = dragStartWindowOrigin, let window else {
            super.mouseDragged(with: event)
            return
        }

        let currentPoint = NSEvent.mouseLocation
        let deltaX = currentPoint.x - startPoint.x
        let deltaY = currentPoint.y - startPoint.y
        window.setFrameOrigin(NSPoint(x: startOrigin.x + deltaX, y: startOrigin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartScreenPoint = nil
        dragStartWindowOrigin = nil
        super.mouseUp(with: event)
    }
}
