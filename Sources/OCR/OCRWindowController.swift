import AppKit

final class OCRWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let onClose: (OCRWindowController) -> Void
    private let textView = NSTextView()
    private let characterCountLabel = NSTextField(labelWithString: "")
    private var isExpanded = false

    init(text: String, onClose: @escaping (OCRWindowController) -> Void) {
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 398, height: 132),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.ocrResult)
        window.minSize = NSSize(width: 360, height: 116)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()

        super.init(window: window)

        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        configureTextView(with: text)

        let contentView = MoliCardView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: L10n.text(.ocrResult).lowercased())
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = MoliDesign.secondaryText
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyButton = makeIconButton(symbol: "doc.on.doc", tooltip: L10n.text(.copy), action: #selector(copyText))
        let expandButton = makeIconButton(symbol: "plus", tooltip: L10n.text(.expand), action: #selector(toggleExpanded))

        let toolbar = NSStackView(views: [copyButton, expandButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        characterCountLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        characterCountLabel.textColor = MoliDesign.tertiaryText
        characterCountLabel.alignment = .center
        characterCountLabel.translatesAutoresizingMaskIntoConstraints = false
        updateCharacterCount()

        let textSymbol = NSTextField(labelWithString: "T")
        textSymbol.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        textSymbol.textColor = MoliDesign.secondaryText
        textSymbol.alignment = .center
        textSymbol.translatesAutoresizingMaskIntoConstraints = false
        textSymbol.setAccessibilityElement(false)

        contentView.addSubview(titleLabel)
        contentView.addSubview(toolbar)
        contentView.addSubview(scrollView)
        contentView.addSubview(characterCountLabel)
        contentView.addSubview(textSymbol)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 108),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toolbar.leadingAnchor, constant: -12),

            toolbar.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 48),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: characterCountLabel.topAnchor, constant: -4),

            characterCountLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            characterCountLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),

            textSymbol.centerYAnchor.constraint(equalTo: characterCountLabel.centerYAnchor),
            textSymbol.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            textSymbol.widthAnchor.constraint(equalToConstant: 18)
        ])
        window.delegate = self
        window.initialFirstResponder = textView

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

    func textDidChange(_ notification: Notification) {
        updateCharacterCount()
    }

    private func configureTextView(with text: String) {
        let displayText = text.isEmpty ? L10n.text(.noTextDetected) : text
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.lineBreakMode = .byWordWrapping

        textView.string = displayText
        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.frame = NSRect(x: 0, y: 0, width: 350, height: 54)
        textView.minSize = NSSize(width: 0, height: 54)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = font
        textView.textColor = MoliDesign.primaryText
        textView.insertionPointColor = MoliDesign.accent
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: 350, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        textView.selectedTextAttributes = [
            .backgroundColor: MoliDesign.selection,
            .foregroundColor: MoliDesign.primaryText
        ]

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: MoliDesign.primaryText,
            .paragraphStyle: paragraphStyle
        ]
        textView.typingAttributes = attributes
        textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: displayText.utf16.count))
    }

    private func makeIconButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = MoliDesign.icon
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        return button
    }

    private func updateCharacterCount() {
        characterCountLabel.stringValue = L10n.text(.ocrCharacterCount, "\(textView.string.count)")
    }

    @objc private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
    }

    @objc private func toggleExpanded() {
        guard let window else { return }
        let delta: CGFloat = isExpanded ? -180 : 180
        var frame = window.frame
        frame.origin.y -= delta
        frame.size.height += delta
        isExpanded.toggle()
        window.setFrame(frame, display: true, animate: true)
    }
}
