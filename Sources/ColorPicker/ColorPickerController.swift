import AppKit

/// Uses NSColorSampler for a quick native picker, then writes the result to
/// clipboard and shows a small HUD.
final class ColorPickerController {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }

    func begin() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] color in
            defer { self?.onClose() }
            guard let color = color else { return }
            let hex = color.hexString
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hex, forType: .string)
            self?.showHUD(color: color, hex: hex)
        }
    }

    private func showHUD(color: NSColor, hex: String) {
        let size = NSSize(width: 220, height: 70)
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width, height: size.height
        )
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.hasShadow = true

        let view = MoliCardView(
            frame: NSRect(origin: .zero, size: size),
            fillColor: MoliDesign.card,
            borderColor: MoliDesign.hairline,
            cornerRadius: 10
        )

        let swatch = NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 50))
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 6
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = MoliDesign.hairline.cgColor
        view.addSubview(swatch)

        let label = NSTextField(labelWithString: "\(hex)\n\(L10n.text(.copiedToClipboard))")
        label.frame = NSRect(x: 70, y: 8, width: 140, height: 55)
        label.textColor = MoliDesign.primaryText
        label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        label.maximumNumberOfLines = 2
        view.addSubview(label)

        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }
}
