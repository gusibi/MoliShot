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
    }

    required init?(coder: NSCoder) { fatalError() }

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
    private let toolbar: NSStackView

    init(frame: NSRect, image: NSImage) {
        self.imageView = DraggablePinImageView(frame: frame)
        self.imageView.image = image
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.autoresizingMask = [.width, .height]

        self.toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        toolbar.layer?.cornerRadius = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.alphaValue = 0

        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        layer?.masksToBounds = true

        addSubview(imageView)
        addSubview(toolbar)

        let closeBtn = makeBtn("xmark.circle.fill", sel: #selector(closeTap))
        let copyBtn = makeBtn("doc.on.doc", sel: #selector(copyTap))
        let saveBtn = makeBtn("arrow.down.circle", sel: #selector(saveTap))
        let ocrBtn = makeBtn("textformat", sel: #selector(ocrTap))
        [closeBtn, copyBtn, saveBtn, ocrBtn].forEach { toolbar.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])

        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeBtn(_ symbol: String, sel: Selector) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.contentTintColor = .white
        b.target = self
        b.action = sel
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toolbar.animator().alphaValue = 1
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            toolbar.animator().alphaValue = 0
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
