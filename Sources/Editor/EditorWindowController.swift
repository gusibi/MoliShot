import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate, EditorViewDelegate {

    private let editorView: EditorView
    private let onClose: (EditorWindowController) -> Void

    private let scrollView = NSScrollView()
    private let clipView = CenteringClipView()
    private let toolBarView = NSVisualEffectView()
    private let toolBarStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    private var toolButtons: [AnnotationTool: NSButton] = [:]

    private let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
    private let strokeSlider = NSSlider()
    private let fontSizeSlider = NSSlider()
    private let fontSizeContainer = NSStackView()  // hides font size when not editing text
    private let opacitySlider = NSSlider()
    private let effectSlider = NSSlider()
    private let effectContainer = NSStackView()  // blur radius / pixelate size, conditional
    private let fillWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
    private let fillCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let fillContainer = NSStackView()  // fill colour + on/off, conditional

    private var eventMonitor: Any?
    private var lastImageSize: NSSize
    private var transientStatusTimer: Timer?
    private var transientStatusMessage: String?

    init(image: NSImage, onClose: @escaping (EditorWindowController) -> Void) {
        self.editorView = EditorView(image: image)
        self.onClose = onClose
        self.lastImageSize = image.size

        let size = EditorWindowController.fitSize(for: image.size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 1080, height: 420)
        window.center()
        window.collectionBehavior = [.fullScreenPrimary]

        super.init(window: window)

        window.delegate = self
        editorView.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil)
        window.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new, .old], context: nil)
        setupUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        window?.removeObserver(self, forKeyPath: "effectiveAppearance")
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func fitSize(for imageSize: NSSize) -> NSSize {
        let maxW: CGFloat = 1400
        let maxH: CGFloat = 900
        var w = imageSize.width
        var h = imageSize.height
        if w > maxW { h *= maxW / w; w = maxW }
        if h > maxH { w *= maxH / h; h = maxH }
        return NSSize(width: max(1080, w + 40), height: max(420, h + 120))
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        configureToolbar()

        toolBarView.translatesAutoresizingMaskIntoConstraints = false
        toolBarView.material = .headerView
        toolBarView.blendingMode = .withinWindow
        toolBarView.state = .active
        toolBarView.addSubview(toolBarStack)

        toolBarStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.borderType = .noBorder
        scrollView.contentView = clipView
        scrollView.documentView = editorView
        let checkerboard = Self.checkerboardColor()
        scrollView.backgroundColor = checkerboard
        scrollView.drawsBackground = true
        clipView.drawsBackground = true
        clipView.backgroundColor = checkerboard

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = MoliDesign.secondaryText

        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        zoomLabel.textColor = MoliDesign.secondaryText

        content.addSubview(toolBarView)
        content.addSubview(scrollView)
        content.addSubview(statusLabel)
        content.addSubview(zoomLabel)

        NSLayoutConstraint.activate([
            toolBarView.topAnchor.constraint(equalTo: content.topAnchor),
            toolBarView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolBarView.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            toolBarStack.topAnchor.constraint(equalTo: toolBarView.topAnchor, constant: 5),
            toolBarStack.leadingAnchor.constraint(equalTo: toolBarView.leadingAnchor, constant: 84),
            toolBarStack.trailingAnchor.constraint(equalTo: toolBarView.trailingAnchor, constant: -10),
            toolBarStack.bottomAnchor.constraint(equalTo: toolBarView.bottomAnchor, constant: -5),

            scrollView.topAnchor.constraint(equalTo: toolBarView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: zoomLabel.leadingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),

            zoomLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            zoomLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
            zoomLabel.heightAnchor.constraint(equalToConstant: 16),
        ])

        updateStatusLabel()
        DispatchQueue.main.async { [weak self] in
            self?.zoomToFit()
            self?.installEventMonitor()
        }
    }

    private func configureToolbar() {
        window?.title = ""
        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        window?.toolbar = nil
        window?.toolbarStyle = .unified
        buildCompactToolbar()
    }

    private func buildCompactToolbar() {
        toolButtons.removeAll()
        toolBarStack.arrangedSubviews.forEach {
            toolBarStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        toolBarStack.orientation = .horizontal
        toolBarStack.alignment = .centerY
        toolBarStack.spacing = 5

        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.pin), symbol: "pin", action: #selector(pinImage)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.copy), symbol: "doc.on.doc", action: #selector(copyImage)))
        toolBarStack.addArrangedSubview(toolbarSeparator())

        for tool in AnnotationTool.allCases where tool != .crop {
            let button = compactToolbarButton(title: tool.title, symbol: tool.symbol, action: #selector(compactToolTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.setButtonType(.toggle)
            toolButtons[tool] = button
            toolBarStack.addArrangedSubview(button)
        }

        toolBarStack.addArrangedSubview(toolbarSeparator())

        colorWell.controlSize = .regular
        colorWell.color = editorView.strokeColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        toolBarStack.addArrangedSubview(colorWell)

        strokeSlider.doubleValue = Double(editorView.strokeWidth)
        strokeSlider.minValue = 1
        strokeSlider.maxValue = 12
        strokeSlider.controlSize = .regular
        strokeSlider.target = self
        strokeSlider.action = #selector(strokeChanged(_:))
        strokeSlider.widthAnchor.constraint(equalToConstant: 78).isActive = true
        toolBarStack.addArrangedSubview(strokeSlider)

        fontSizeSlider.doubleValue = Double(editorView.fontSize)
        fontSizeSlider.minValue = 8
        fontSizeSlider.maxValue = 72
        fontSizeSlider.controlSize = .regular
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged(_:))
        fontSizeSlider.widthAnchor.constraint(equalToConstant: 78).isActive = true
        fontSizeContainer.orientation = .horizontal
        fontSizeContainer.addArrangedSubview(fontSizeSlider)
        fontSizeContainer.isHidden = true  // shown only when a text annotation is selected
        toolBarStack.addArrangedSubview(fontSizeContainer)

        opacitySlider.doubleValue = 100
        opacitySlider.minValue = 0
        opacitySlider.maxValue = 100
        opacitySlider.controlSize = .regular
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.widthAnchor.constraint(equalToConstant: 60).isActive = true
        toolBarStack.addArrangedSubview(opacitySlider)

        effectSlider.controlSize = .regular
        effectSlider.target = self
        effectSlider.action = #selector(effectChanged(_:))
        effectSlider.widthAnchor.constraint(equalToConstant: 60).isActive = true
        effectContainer.orientation = .horizontal
        effectContainer.addArrangedSubview(effectSlider)
        effectContainer.isHidden = true  // shown only when a blur/pixelate annotation is selected
        toolBarStack.addArrangedSubview(effectContainer)

        fillWell.controlSize = .regular
        fillWell.target = self
        fillWell.action = #selector(fillColorChanged(_:))
        fillCheckbox.setButtonType(.switch)
        fillCheckbox.target = self
        fillCheckbox.action = #selector(fillToggleChanged(_:))
        fillContainer.orientation = .horizontal
        fillContainer.addArrangedSubview(fillCheckbox)
        fillContainer.addArrangedSubview(fillWell)
        fillContainer.isHidden = true  // shown only for rect/ellipse/highlight
        toolBarStack.addArrangedSubview(fillContainer)

        toolBarStack.addArrangedSubview(toolbarSeparator())
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.crop), symbol: "crop", action: #selector(toggleCropMode)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.undo), symbol: "arrow.uturn.backward", action: #selector(undoTap)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.redo), symbol: "arrow.uturn.forward", action: #selector(redoTap)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.clear), symbol: "trash", action: #selector(clearTap)))

        toolBarStack.addArrangedSubview(toolbarSeparator())
        toolBarStack.addArrangedSubview(compactToolbarButton(title: "-", symbol: "minus.magnifyingglass", action: #selector(zoomOut)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: "100%", symbol: "1.magnifyingglass", action: #selector(actualSize)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.fit), symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fitToWindow)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: "+", symbol: "plus.magnifyingglass", action: #selector(zoomIn)))

        toolBarStack.addArrangedSubview(toolbarSeparator())
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.ocr), symbol: "text.viewfinder", action: #selector(runOCR)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.save), symbol: "square.and.arrow.down", action: #selector(saveImage)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.upload), symbol: "icloud.and.arrow.up", action: #selector(uploadImage)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolBarStack.addArrangedSubview(spacer)
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.close), symbol: "xmark", action: #selector(closeEditor)))

        refreshToolButtons()
    }

    private func compactToolbarButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.controlSize = .regular
        button.isBordered = false
        button.wantsLayer = true
        button.image = toolbarSymbol(symbol, title: title)
        button.imagePosition = .imageOnly
        button.contentTintColor = MoliDesign.icon
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        styleToolbarButton(button, isSelected: false)
        return button
    }

    private func toolbarSymbol(_ symbol: String, title: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
    }

    private func toolbarSeparator() -> NSView {
        let separator = MoliCardView(fillColor: MoliDesign.hairline, cornerRadius: 0)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return separator
    }

    private static func checkerboardColor() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return makeCheckerboardPattern(isDark: isDark)
        }
    }

    private static func makeCheckerboardPattern(isDark: Bool) -> NSColor {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let c1 = NSColor(calibratedWhite: isDark ? 0.12 : 0.98, alpha: 1)
        let c2 = NSColor(calibratedWhite: isDark ? 0.18 : 0.92, alpha: 1)
        c1.setFill()
        NSRect(origin: .zero, size: size).fill()
        c2.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        NSRect(x: 8, y: 8, width: 8, height: 8).fill()
        image.unlockFocus()
        return NSColor(patternImage: image)
    }

    private func refreshToolButtons() {
        for (tool, button) in toolButtons {
            let isSelected = editorView.currentTool == tool
            button.state = isSelected ? .on : .off
            styleToolbarButton(button, isSelected: isSelected)
        }
    }

    private func styleToolbarButton(_ button: NSButton, isSelected: Bool) {
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = MoliDesign.toolbarFill(isSelected: isSelected).cgColor
        button.layer?.borderWidth = isSelected ? 1 : 0
        button.layer?.borderColor = MoliDesign.hairline.cgColor
        button.contentTintColor = isSelected ? MoliDesign.primaryText : MoliDesign.icon
    }

    // MARK: - Toolbar actions

    @objc private func compactToolTapped(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let tool = AnnotationTool(rawValue: rawValue)
        else {
            return
        }
        editorView.commitActiveTextEditing()
        editorView.currentTool = tool
        refreshToolButtons()
        updateStatusLabel(tool: tool)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        editorView.setStrokeColor(sender.color)
    }

    @objc private func strokeChanged(_ sender: NSSlider) {
        editorView.setStrokeWidth(CGFloat(sender.doubleValue))
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) {
        editorView.setFontSize(CGFloat(sender.doubleValue))
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        editorView.setOpacity(CGFloat(sender.doubleValue / 100))
    }

    @objc private func effectChanged(_ sender: NSSlider) {
        let v = CGFloat(sender.doubleValue)
        if editorView.selectedIsBlur {
            editorView.setBlurRadius(v)
        } else if editorView.selectedIsPixelate {
            editorView.setPixelSize(v)
        }
    }

    @objc private func fillColorChanged(_ sender: NSColorWell) {
        editorView.setFillColor(sender.color)
    }

    @objc private func fillToggleChanged(_ sender: NSButton) {
        editorView.setFillEnabled(sender.state == .on)
    }

    @objc private func closeEditor() { close() }

    @objc private func toggleCropMode() {
        if editorView.cropMode {
            // Already editing — second click cancels.
            editorView.cancelCropMode()
        } else {
            editorView.enterCropMode()
        }
    }

    @objc private func undoTap() {
        switch editorView.undo() {
        case .cancelledTextEditing:
            showTransientStatus(L10n.text(.editingCancelled))
        case .cancelledPendingInteraction:
            showTransientStatus(L10n.text(.selectionCancelled))
        case .undid:
            showTransientStatus(L10n.text(.undoApplied))
        case .nothingToUndo:
            showTransientStatus(L10n.text(.nothingToUndo))
        case .redid, .nothingToRedo:
            break
        }
    }

    @objc private func redoTap() {
        switch editorView.redo() {
        case .redid:
            showTransientStatus(L10n.text(.redoApplied))
        case .nothingToRedo:
            showTransientStatus(L10n.text(.nothingToRedo))
        case .cancelledTextEditing, .cancelledPendingInteraction, .undid, .nothingToUndo:
            break
        }
    }

    @objc private func clearTap() {
        if editorView.clearAll() {
            showTransientStatus(L10n.text(.clearedAnnotations))
        }
    }
    @objc private func zoomIn() { changeZoom(by: 1.25) }
    @objc private func zoomOut() { changeZoom(by: 0.8) }
    @objc private func actualSize() { setZoom(1, centerAt: visibleCenter()) }
    @objc private func fitToWindow() { zoomToFit() }

    @objc private func runOCR() {
        showTransientStatus(L10n.text(.ocrInProgress), autoClear: false)
        let image = editorView.renderFinalImage()
        OCRService.shared.recognize(in: image) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    self?.showTransientStatus(text.isEmpty ? L10n.text(.noTextDetected) : L10n.text(.ocrCopiedToClipboard))
                    AppCoordinator.shared.showOCRResult(text)
                case .failure(let error):
                    self?.showTransientStatus(L10n.text(.ocrFailed))
                    AppCoordinator.shared.presentAlert(title: L10n.text(.ocr), message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func pinImage() {
        AppCoordinator.shared.pinImage(editorView.renderFinalImage())
        close()
    }

    @objc private func copyImage() {
        let image = editorView.renderFinalImage()
        NSPasteboard.general.writeImage(image)
        showTransientStatus(L10n.text(.copiedToClipboard))
    }

    @objc private func saveImage() {
        do {
            let url = try AppSettings.save(image: editorView.renderFinalImage(), prefix: "Screenshot")
            showTransientStatus(L10n.text(.saved, url.lastPathComponent), duration: 3)
        } catch {
            showTransientStatus(L10n.text(.saveFailed, error.localizedDescription), duration: 4)
        }
    }

    @objc private func uploadImage() {
        showTransientStatus(L10n.text(.uploadInProgress), autoClear: false)
        let image = editorView.renderFinalImage()
        UploadService.shared.upload(image: image) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    self?.showTransientStatus(L10n.text(.uploaded, url.absoluteString), duration: 4)
                case .failure(let err):
                    self?.showTransientStatus(L10n.text(.uploadFailed, err.localizedDescription), duration: 4)
                }
            }
        }
    }

    // MARK: - EditorViewDelegate

    func editorViewDidChangeSelection(_ view: EditorView) {
        updateStatusLabel()
        syncStyleControls(to: view)
    }

    /// Reflect the effective style (selection's, or defaults) in the color,
    /// stroke, and font-size controls; hide font size unless a text annotation
    /// is selected.
    private func syncStyleControls(to view: EditorView) {
        let style = view.effectiveStyle
        colorWell.color = style.color
        strokeSlider.doubleValue = Double(style.strokeWidth)
        fontSizeSlider.doubleValue = Double(style.fontSize)
        opacitySlider.doubleValue = Double(style.opacity * 100)
        fontSizeContainer.isHidden = !view.selectedIsText

        let isBlur = view.selectedIsBlur
        let isPixelate = view.selectedIsPixelate
        effectContainer.isHidden = !(isBlur || isPixelate)
        if isBlur {
            effectSlider.minValue = 1; effectSlider.maxValue = 50
            effectSlider.doubleValue = Double(view.selectedEffectValue)
        } else if isPixelate {
            effectSlider.minValue = 2; effectSlider.maxValue = 40
            effectSlider.doubleValue = Double(view.selectedEffectValue)
        }

        let supportsFill = view.selectedSupportsFill
        fillContainer.isHidden = !supportsFill
        if supportsFill {
            let fc = view.effectiveFillColor
            fillCheckbox.state = fc == nil ? .off : .on
            fillWell.color = fc ?? view.effectiveStyle.color
        }
    }
    func editorViewDidChangeContent(_ view: EditorView) {
        if !lastImageSize.equalTo(view.effectiveSize) {
            lastImageSize = view.effectiveSize
            zoomToFit()
        } else {
            updateStatusLabel()
        }
    }
    func editorViewDidChangeTool(_ view: EditorView) {
        refreshToolButtons()
        updateStatusLabel()
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        transientStatusTimer?.invalidate()
        onClose(self)
    }

    func windowDidResize(_ notification: Notification) {
        recenterImageIfNeeded()
        updateStatusLabel()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            refreshToolButtons()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow == true else { return event }
            if self.window?.firstResponder is NSTextView { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .shift] {
                switch event.charactersIgnoringModifiers {
                case "z":
                    self.redoTap()
                    return nil
                case "]":
                    self.editorView.bringToFront()
                    return nil
                case "[":
                    self.editorView.sendToBack()
                    return nil
                default:
                    break
                }
            } else if flags == [.command] {
                switch event.charactersIgnoringModifiers {
                case "+", "=":
                    self.zoomIn()
                    return nil
                case "-":
                    self.zoomOut()
                    return nil
                case "0":
                    self.fitToWindow()
                    return nil
                case "1":
                    self.actualSize()
                    return nil
                case "c":
                    if self.editorView.hasSelection {
                        _ = self.editorView.copySelection()
                        self.showTransientStatus(L10n.text(.copiedToClipboard))
                    } else {
                        self.copyImage()
                    }
                    return nil
                case "v":
                    if self.editorView.paste() {
                        self.showTransientStatus(L10n.text(.pastedAnnotation))
                    } else {
                        self.copyImage()  // no annotation data; nothing else to paste
                    }
                    return nil
                case "d":
                    if self.editorView.duplicateSelection() {
                        self.showTransientStatus(L10n.text(.duplicatedAnnotation))
                    }
                    return nil
                case "s":
                    self.saveImage()
                    return nil
                case "z":
                    self.undoTap()
                    return nil
                case "]":
                    self.editorView.bringForward()
                    return nil
                case "[":
                    self.editorView.sendBackward()
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    private func changeZoom(by factor: CGFloat) {
        let next = scrollView.magnification * factor
        setZoom(next, centerAt: visibleCenter())
    }

    private func setZoom(_ value: CGFloat, centerAt center: NSPoint) {
        let clamped = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        scrollView.setMagnification(clamped, centeredAt: center)
        recenterImageIfNeeded()
        updateStatusLabel()
    }

    private func zoomToFit() {
        let visibleSize = scrollView.contentSize
        let imageSize = editorView.effectiveSize
        guard visibleSize.width > 0, visibleSize.height > 0, imageSize.width > 0, imageSize.height > 0 else { return }
        let widthFit = visibleSize.width / imageSize.width
        let heightFit = visibleSize.height / imageSize.height
        let target = min(widthFit, heightFit)
        setZoom(target, centerAt: NSPoint(x: imageSize.width / 2, y: imageSize.height / 2))
    }

    private func visibleCenter() -> NSPoint {
        let rect = editorView.visibleRect
        if rect.isEmpty {
            return NSPoint(x: editorView.bounds.midX, y: editorView.bounds.midY)
        }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func recenterImageIfNeeded() {
        let constrained = clipView.constrainBoundsRect(clipView.bounds)
        guard constrained.origin != clipView.bounds.origin else { return }
        clipView.setBoundsOrigin(constrained.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func updateStatusLabel(tool: AnnotationTool? = nil) {
        let activeTool = tool ?? editorView.currentTool
        let pointSize = editorView.effectiveSize
        let fullPoint = editorView.baseImage.size
        let fullPixel = editorView.baseImage.pixelSize ?? fullPoint
        let scaleX = fullPoint.width > 0 ? fullPixel.width / fullPoint.width : 1
        let scaleY = fullPoint.height > 0 ? fullPixel.height / fullPoint.height : 1
        let pixelSize = NSSize(width: pointSize.width * scaleX, height: pointSize.height * scaleY)
        if let transientStatusMessage {
            statusLabel.stringValue = transientStatusMessage
        } else {
            statusLabel.stringValue = "\(Int(pointSize.width))×\(Int(pointSize.height)) pt  /  \(Int(pixelSize.width))×\(Int(pixelSize.height)) px  —  \(editorView.annotations.count) \(L10n.text(.annotations))  —  \(activeTool.title)"
        }
        zoomLabel.stringValue = "\(Int((scrollView.magnification * 100).rounded()))%"
    }

    @objc private func languageDidChange() {
        configureToolbar()
        updateStatusLabel()
    }

    private func showTransientStatus(_ message: String, duration: TimeInterval = 2.2, autoClear: Bool = true) {
        transientStatusTimer?.invalidate()
        transientStatusMessage = message
        updateStatusLabel()
        guard autoClear else { return }
        transientStatusTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.transientStatusMessage = nil
            self?.updateStatusLabel()
        }
    }
}

private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)

        guard let documentFrame = documentView?.frame else {
            return constrained
        }

        if documentFrame.width < proposedBounds.width {
            constrained.origin.x = (documentFrame.width - proposedBounds.width) / 2
        }

        if documentFrame.height < proposedBounds.height {
            constrained.origin.y = (documentFrame.height - proposedBounds.height) / 2
        }

        return constrained
    }
}
