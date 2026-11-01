import AppKit
import QuartzCore

/// NSTextStorage holds resolved foreground attributes; refresh them together with
/// the editor surface when a window changes appearance, including pasted text.
private final class OCRTextView: NSTextView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = .textBackgroundColor
            textColor = .textColor
            insertionPointColor = .textColor
            selectedTextAttributes = [
                .backgroundColor: NSColor.selectedTextBackgroundColor,
                .foregroundColor: NSColor.selectedTextColor
            ]
        }
    }
}

final class OCRWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let pasteboard: NSPasteboard
    private let onClose: (OCRWindowController) -> Void
    private let textView = OCRTextView()
    private let characterCountLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var copyButton: NSButton!
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var editingButtons: [NSButton] = []
    private let scrollView = NSScrollView()
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: L10n.text(.ocrInProgress))
    private var feedbackReset: DispatchWorkItem?
    private var fontSize: CGFloat = 16
    private var isRecognizing = true
    private var isClosed = false

    init(pasteboard: NSPasteboard = .general, onClose: @escaping (OCRWindowController) -> Void) {
        self.pasteboard = pasteboard
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.ocrResult)
        window.minSize = NSSize(width: 500, height: 340)
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.center()

        super.init(window: window)
        configureTextView(with: "")
        let contentView = MoliCardView(fillColor: .windowBackgroundColor, cornerRadius: 0)
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: L10n.text(.ocrResult))
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .labelColor
        let subtitle = NSTextField(labelWithString: L10n.text(.ocrEditorHint))
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [titleLabel, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 6

        let symbol = NSImageView(image: NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)!)
        symbol.contentTintColor = .controlAccentColor
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        symbol.setAccessibilityElement(false)
        let header = NSStackView(views: [heading, NSView(), symbol])
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(header)

        undoButton = makeButton(symbol: "arrow.uturn.backward", tooltip: L10n.text(.undo), action: #selector(undo(_:)))
        redoButton = makeButton(symbol: "arrow.uturn.forward", tooltip: L10n.text(.redo), action: #selector(redo(_:)))
        let find = makeButton(symbol: "magnifyingglass", tooltip: L10n.text(.ocrFind), action: #selector(findText))
        find.keyEquivalent = "f"
        find.keyEquivalentModifierMask = .command
        let smaller = makeButton(symbol: "textformat.size.smaller", tooltip: L10n.text(.ocrSmallerText), action: #selector(smallerText))
        let larger = makeButton(symbol: "textformat.size.larger", tooltip: L10n.text(.ocrLargerText), action: #selector(largerText))
        editingButtons = [find, smaller, larger]
        characterCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        characterCountLabel.textColor = .secondaryLabelColor
        characterCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let tools = NSStackView(views: [undoButton, redoButton, separator(), find, separator(), smaller, larger, NSView(), characterCountLabel])
        tools.spacing = 6
        tools.alignment = .centerY
        tools.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tools)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.findBarPosition = .aboveContent
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let editor = MoliCardView(fillColor: .textBackgroundColor, borderColor: .separatorColor, cornerRadius: 12)
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.addSubview(scrollView)
        contentView.addSubview(editor)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: editor.topAnchor, constant: 1),
            scrollView.leadingAnchor.constraint(equalTo: editor.leadingAnchor, constant: 1),
            scrollView.trailingAnchor.constraint(equalTo: editor.trailingAnchor, constant: -1),
            scrollView.bottomAnchor.constraint(equalTo: editor.bottomAnchor, constant: -1)
        ])

        copyButton = NSButton(title: L10n.text(.copy), target: self, action: #selector(copyText))
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .large
        copyButton.bezelColor = .controlAccentColor
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        copyButton.toolTip = L10n.text(.copy)
        copyButton.setAccessibilityLabel(L10n.text(.copy))
        copyButton.keyEquivalent = "\r"
        copyButton.keyEquivalentModifierMask = .command
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        let footer = NSStackView(views: [statusLabel, NSView(), copyButton])
        footer.alignment = .centerY
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footer)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressLabel.font = NSFont.systemFont(ofSize: 13)
        progressLabel.textColor = .secondaryLabelColor
        let progressStack = NSStackView(views: [progressIndicator, progressLabel])
        progressStack.spacing = 10
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        editor.addSubview(progressStack)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            tools.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            tools.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            tools.heightAnchor.constraint(equalToConstant: 30),
            editor.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 10),
            editor.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            editor.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            editor.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            progressStack.centerXAnchor.constraint(equalTo: editor.centerXAnchor),
            progressStack.centerYAnchor.constraint(equalTo: editor.centerYAnchor)
        ])
        scrollView.isHidden = true
        updateActions()
        progressIndicator.startAnimation(nil)
        window.delegate = self
        window.initialFirstResponder = textView
    }

    required init?(coder: NSCoder) { fatalError() }

    func completeRecognition(_ result: Result<String, OCRServiceError>) {
        guard isRecognizing, !isClosed else { return }
        isRecognizing = false
        progressIndicator.stopAnimation(nil)
        progressIndicator.superview?.isHidden = true
        scrollView.isHidden = false
        switch result {
        case .success(let text):
            configureTextView(with: text)
            textView.isEditable = !text.isEmpty
            if !text.isEmpty {
                updateCharacterCount()
                // Preserve automatic clipboard delivery without implying a click.
                copyTextToPasteboard(automatically: true)
                window?.makeFirstResponder(textView)
            } else {
                statusLabel.stringValue = L10n.text(.noTextDetected)
            }
        case .failure(let error):
            textView.string = error.localizedDescription
            textView.isEditable = false
            statusLabel.stringValue = L10n.text(.ocrFailed)
        }
        updateActions()
        if !MoliDesign.reduceMotion {
            scrollView.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.animator().alphaValue = 1
            }
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        feedbackReset?.cancel()
        progressIndicator.stopAnimation(nil)
        onClose(self)
    }

    func textDidChange(_ notification: Notification) {
        resetCopyFeedback()
        statusLabel.stringValue = L10n.text(.ocrEditing)
        updateCharacterCount()
        updateActions()
    }

    private func configureTextView(with text: String) {
        let displayText = text.isEmpty ? L10n.text(.noTextDetected) : text
        textView.string = displayText
        textView.delegate = self
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.frame = NSRect(x: 0, y: 0, width: 590, height: 230)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: 554, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = true
        applyFont()
        textView.refreshColors()
        textView.undoManager?.removeAllActions()
        textView.setAccessibilityLabel(L10n.text(.ocrResult))
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.contentTintColor = .secondaryLabelColor
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return line
    }

    private func applyFont() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        paragraphStyle.lineBreakMode = .byWordWrapping
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.defaultParagraphStyle = paragraphStyle
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: textView.string.utf16.count))
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func updateActions() {
        let editable = !isRecognizing && textView.isEditable
        copyButton?.isEnabled = editable && !textView.string.isEmpty
        editingButtons.forEach { $0.isEnabled = editable }
        undoButton?.isEnabled = editable && (textView.undoManager?.canUndo ?? false)
        redoButton?.isEnabled = editable && (textView.undoManager?.canRedo ?? false)
    }

    private func updateCharacterCount() {
        characterCountLabel.stringValue = L10n.text(.ocrCharacterCount, "\(textView.string.count)")
    }

    @objc func undo(_ sender: Any?) {
        textView.undoManager?.undo()
        updateActions()
    }

    @objc func redo(_ sender: Any?) {
        textView.undoManager?.redo()
        updateActions()
    }

    @objc private func findText() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performFindPanelAction(item)
    }

    @objc private func smallerText() {
        fontSize = max(12, fontSize - 1)
        applyFont()
    }

    @objc private func largerText() {
        fontSize = min(28, fontSize + 1)
        applyFont()
    }

    @objc private func copyText() {
        guard copyButton.isEnabled else { return }
        copyTextToPasteboard(automatically: false)
    }

    private func copyTextToPasteboard(automatically: Bool) {
        resetCopyFeedback()
        pasteboard.clearContents()
        let succeeded = pasteboard.setString(textView.string, forType: .string)
        let message = L10n.text(succeeded ? (automatically ? .ocrAutomaticallyCopied : .ocrCopied) : .ocrCopyFailed)
        statusLabel.stringValue = message
        if succeeded && !automatically {
            copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            copyButton.title = L10n.text(.ocrCopied)
            copyButton.setAccessibilityLabel(message)
        }
        NSAccessibility.post(element: statusLabel, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        if !automatically {
            let reset = DispatchWorkItem { [weak self] in
                self?.resetCopyFeedback()
                self?.statusLabel.stringValue = L10n.text(.ocrReady)
            }
            feedbackReset = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: reset)
        }
    }

    private func resetCopyFeedback() {
        feedbackReset?.cancel()
        feedbackReset = nil
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.title = L10n.text(.copy)
        copyButton.setAccessibilityLabel(L10n.text(.copy))
    }
}
