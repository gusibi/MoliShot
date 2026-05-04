import AppKit

final class OCRWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: (OCRWindowController) -> Void
    private let textView = NSTextView()

    init(text: String, onClose: @escaping (OCRWindowController) -> Void) {
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.ocrResult)
        window.minSize = NSSize(width: 380, height: 260)
        window.center()

        super.init(window: window)

        textView.string = text.isEmpty ? L10n.text(.noTextDetected) : text
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isEditable = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = false

        let copyButton = NSButton(title: L10n.text(.copy), target: nil, action: #selector(copyText))
        copyButton.target = self
        copyButton.bezelStyle = .rounded
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L10n.text(.copy))
        copyButton.imagePosition = .imageLeading

        let header = NSStackView(views: [NSView(), copyButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 6, right: 12)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder

        let root = NSStackView(views: [header, scrollView])
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(root)
        window.contentView = contentView
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        window.delegate = self

        if !text.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }

    @objc private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
    }
}
