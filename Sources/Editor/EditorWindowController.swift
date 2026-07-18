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
    private var toolButtons: [AnnotationTool: MoliHoverButton] = [:]
    private var cropButton: MoliHoverButton?
    private var cropConfirmBar: CropConfirmBar?
    private var overflowButton: MoliHoverButton?
    /// Collapsible style controls (swatches + sliders) and their group
    /// separators, tucked into the overflow popover when the window is narrow.
    private var styleGroup: NSStackView?
    private var styleSeparators: [NSView] = []
    private var styleCollapsed = false
    private var lastExpandedWidth: CGFloat = 1040

    private let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
    private var colorSwatches: [ColorSwatchButton] = []
    private let strokeSlider = NSSlider()
    private let fontSizeSlider = NSSlider()
    private let fontSizeContainer = NSStackView()  // hides font size when not editing text
    private let opacitySlider = NSSlider()
    private let effectSlider = NSSlider()
    private let effectContainer = NSStackView()  // blur radius / pixelate size, conditional
    private let fillWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
    private let fillCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let fillContainer = NSStackView()  // fill colour + on/off, conditional
    private let zoomStack = NSStackView()

    private var eventMonitor: Any?
    private var lastImageSize: NSSize
    private var sliderValueRestoreItem: DispatchWorkItem?

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
        window.minSize = NSSize(width: 720, height: 420)
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
        return NSSize(width: max(720, w + 40), height: max(420, h + 120))
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

        zoomLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        zoomLabel.textColor = MoliDesign.secondaryText
        configureZoomStack()

        content.addSubview(toolBarView)
        content.addSubview(scrollView)
        content.addSubview(statusLabel)
        content.addSubview(zoomStack)

        NSLayoutConstraint.activate([
            toolBarView.topAnchor.constraint(equalTo: content.topAnchor),
            toolBarView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolBarView.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            toolBarStack.topAnchor.constraint(equalTo: toolBarView.topAnchor, constant: 5),
            toolBarStack.leadingAnchor.constraint(equalTo: toolBarView.leadingAnchor, constant: trafficLightInset()),
            toolBarStack.trailingAnchor.constraint(equalTo: toolBarView.trailingAnchor, constant: -10),
            toolBarStack.bottomAnchor.constraint(equalTo: toolBarView.bottomAnchor, constant: -5),

            scrollView.topAnchor.constraint(equalTo: toolBarView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: zoomStack.leadingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),

            zoomStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            zoomStack.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
        ])

        updateStatusLabel()
        DispatchQueue.main.async { [weak self] in
            self?.zoomToFit(animated: false)
            self?.installEventMonitor()
            self?.updateToolbarCollapse()
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
        toolBarStack.spacing = 3
        // Hidden arranged subviews are removed from layout (no stranded gaps).
        toolBarStack.detachesHiddenViews = true
        styleSeparators.removeAll()

        // Annotation tools + crop.
        for tool in AnnotationTool.allCases where tool != .crop {
            let button = compactToolbarButton(title: tool.title, symbol: tool.symbol, action: #selector(compactToolTapped(_:)), shortcut: tool.shortcutKey)
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.setButtonType(.toggle)
            toolButtons[tool] = button
            toolBarStack.addArrangedSubview(button)
        }
        let crop = compactToolbarButton(title: L10n.text(.crop), symbol: "crop", action: #selector(toggleCropMode))
        cropButton = crop
        toolBarStack.addArrangedSubview(crop)

        let leadingSep = toolbarSeparator()
        styleSeparators.append(leadingSep)
        toolBarStack.addArrangedSubview(leadingSep)

        // Style controls grouped so they collapse into the overflow popover as a
        // unit when the window is narrow. Preset swatches cover the 95% "red box"
        // case; the well stays as the custom-colour entrypoint.
        toolBarStack.addArrangedSubview(buildStyleGroup())

        let trailingSep = toolbarSeparator()
        styleSeparators.append(trailingSep)
        toolBarStack.addArrangedSubview(trailingSep)

        // History.
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.undo), symbol: "arrow.uturn.backward", action: #selector(undoTap), shortcut: "⌘Z"))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.redo), symbol: "arrow.uturn.forward", action: #selector(redoTap), shortcut: "⇧⌘Z"))

        // Flexible gap pushes the output group to the right edge.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolBarStack.addArrangedSubview(spacer)

        // Overflow entry — reveals the collapsed style controls; hidden until the
        // toolbar actually collapses (see updateToolbarCollapse).
        let overflow = compactToolbarButton(title: L10n.text(.more), symbol: "ellipsis", action: #selector(showOverflowPopover(_:)))
        overflow.isHidden = true
        overflowButton = overflow
        toolBarStack.addArrangedSubview(overflow)

        // Output group. Clear lives here (well away from undo/redo) and turns red
        // on hover; it's non-destructive enough — ⌘Z restores — to skip a dialog.
        toolBarStack.addArrangedSubview(toolbarSeparator())
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.clear), symbol: "trash", action: #selector(clearTap), destructive: true))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.ocr), symbol: "text.viewfinder", action: #selector(runOCR)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.pin), symbol: "pin", action: #selector(pinImage)))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.copy), symbol: "doc.on.doc", action: #selector(copyImage), shortcut: "⌘C"))
        let saveButton = compactToolbarButton(title: L10n.text(.save), symbol: "square.and.arrow.down", action: #selector(saveImage), shortcut: "⌘S")
        saveButton.isProminent = true
        toolBarStack.addArrangedSubview(saveButton)

        toolBarStack.addArrangedSubview(toolbarGap(10))
        toolBarStack.addArrangedSubview(compactToolbarButton(title: L10n.text(.close), symbol: "xmark", action: #selector(closeEditor)))

        styleCollapsed = false
        refreshToolButtons()
    }

    /// Build the collapsible style group: swatch palette, stroke/opacity sliders,
    /// and the contextual font-size / effect / fill containers.
    private func buildStyleGroup() -> NSStackView {
        let group = NSStackView()
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = 3
        group.detachesHiddenViews = true

        group.addArrangedSubview(buildSwatchRow())

        strokeSlider.doubleValue = Double(editorView.strokeWidth)
        strokeSlider.minValue = 1
        strokeSlider.maxValue = 12
        strokeSlider.target = self
        strokeSlider.action = #selector(strokeChanged(_:))
        group.addArrangedSubview(sliderControl(strokeSlider, symbol: "lineweight", tooltip: L10n.text(.strokeWidth), width: 72))

        opacitySlider.doubleValue = 100
        opacitySlider.minValue = 0
        opacitySlider.maxValue = 100
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        group.addArrangedSubview(sliderControl(opacitySlider, symbol: "circle.lefthalf.filled", tooltip: L10n.text(.opacity), width: 58))

        fontSizeSlider.doubleValue = Double(editorView.fontSize)
        fontSizeSlider.minValue = 8
        fontSizeSlider.maxValue = 72
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged(_:))
        configureSliderContainer(fontSizeContainer, slider: fontSizeSlider, symbol: "textformat.size", tooltip: L10n.text(.fontSize), width: 72, in: group)

        effectSlider.target = self
        effectSlider.action = #selector(effectChanged(_:))
        configureSliderContainer(effectContainer, slider: effectSlider, symbol: "wand.and.rays", tooltip: L10n.text(.effectStrength), width: 58, in: group)

        fillWell.controlSize = .regular
        fillWell.target = self
        fillWell.action = #selector(fillColorChanged(_:))
        fillCheckbox.setButtonType(.switch)
        fillCheckbox.target = self
        fillCheckbox.action = #selector(fillToggleChanged(_:))
        fillContainer.orientation = .horizontal
        fillContainer.spacing = 2
        if fillContainer.arrangedSubviews.isEmpty {
            fillContainer.addArrangedSubview(fillCheckbox)
            fillContainer.addArrangedSubview(fillWell)
        }
        fillContainer.isHidden = true  // shown only for rect/ellipse/highlight
        group.addArrangedSubview(fillContainer)

        styleGroup = group
        return group
    }

    private func compactToolbarButton(title: String, symbol: String, action: Selector, shortcut: String? = nil, destructive: Bool = false) -> MoliHoverButton {
        let button = MoliHoverButton()
        button.controlSize = .regular
        button.isDestructive = destructive
        button.image = toolbarSymbol(symbol, title: title)
        button.imagePosition = .imageOnly
        // Tooltip surfaces the shortcut ("Rectangle  R"); the accessibility
        // label stays name-only so VoiceOver doesn't read symbol glyphs.
        button.toolTip = shortcut.map { "\(title)  \($0)" } ?? title
        button.setAccessibilityLabel(title)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    /// Slider prefixed with a small symbol so the user can tell the sliders apart.
    private func sliderControl(_ slider: NSSlider, symbol: String, tooltip: String, width: CGFloat) -> NSStackView {
        let stack = NSStackView()
        configureSliderContainer(stack, slider: slider, symbol: symbol, tooltip: tooltip, width: width)
        stack.isHidden = false
        return stack
    }

    private func configureSliderContainer(_ stack: NSStackView, slider: NSSlider, symbol: String, tooltip: String, width: CGFloat, in parent: NSStackView? = nil) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        icon.contentTintColor = MoliDesign.tertiaryText
        icon.toolTip = tooltip
        stack.addArrangedSubview(icon)

        slider.controlSize = .small
        slider.toolTip = tooltip
        slider.setAccessibilityLabel(tooltip)
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(slider)

        // The contextual containers (font size / effect) start hidden and are
        // parented into the style group so they collapse with it.
        guard let parent else { return }
        stack.isHidden = true
        if parent.arrangedSubviews.contains(stack) == false {
            parent.addArrangedSubview(stack)
        }
    }

    /// Room the toolbar must leave for the traffic-light buttons. Read from the
    /// zoom button's frame so a future system layout change doesn't strand the
    /// old 84pt magic number.
    private func trafficLightInset() -> CGFloat {
        if let zoom = window?.standardWindowButton(.zoomButton), zoom.frame.maxX > 0 {
            return zoom.frame.maxX + 12
        }
        return 84
    }

    private func toolbarGap(_ width: CGFloat = 14) -> NSView {
        let gap = NSView()
        gap.translatesAutoresizingMaskIntoConstraints = false
        gap.widthAnchor.constraint(equalToConstant: width).isActive = true
        return gap
    }

    /// The seven preset stroke colours, stored in sRGB to match how fills are
    /// persisted (and so swatch matching is exact).
    private static let swatchColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white,
    ].map { $0.usingColorSpace(.sRGB) ?? $0 }

    /// Preset swatches followed by the custom-colour well.
    private func buildSwatchRow() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        colorSwatches.removeAll()
        for color in Self.swatchColors {
            let swatch = ColorSwatchButton(color: color)
            swatch.target = self
            swatch.action = #selector(swatchTapped(_:))
            colorSwatches.append(swatch)
            stack.addArrangedSubview(swatch)
        }
        colorWell.controlSize = .regular
        colorWell.color = editorView.strokeColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        stack.addArrangedSubview(colorWell)
        refreshSwatchSelection(current: editorView.effectiveStyle.color)
        return stack
    }

    private func refreshSwatchSelection(current: NSColor) {
        for swatch in colorSwatches {
            swatch.isSelectedSwatch = ColorSwatchButton.colorsMatch(swatch.swatchColor, current)
        }
    }

    /// Collapse the style group into the overflow popover when the toolbar's
    /// natural content width exceeds the space available (with a little
    /// hysteresis so it doesn't flicker at the threshold). Deterministic width
    /// math — NSStackView's visibility-priority auto-detach doesn't fire under a
    /// leading/trailing pin.
    private func updateToolbarCollapse() {
        guard toolBarView.bounds.width > 0 else { return }
        let available = toolBarView.bounds.width - trafficLightInset() - 10
        if styleCollapsed {
            if available >= lastExpandedWidth + 30 { setStyleCollapsed(false) }
        } else {
            lastExpandedWidth = toolBarStack.fittingSize.width
            if available < lastExpandedWidth { setStyleCollapsed(true) }
        }
    }

    private func setStyleCollapsed(_ collapsed: Bool) {
        styleCollapsed = collapsed
        styleGroup?.isHidden = collapsed
        styleSeparators.forEach { $0.isHidden = collapsed }
        overflowButton?.isHidden = !collapsed
    }

    @objc private func showOverflowPopover(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = makeOverflowController()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    /// Rebuild the style controls inside the popover, wired to the same @objc
    /// actions (which read `sender.doubleValue` / `.swatchColor`, so a fresh
    /// control instance works). Seeded with the current effective style.
    private func makeOverflowController() -> NSViewController {
        let vc = NSViewController()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let swatches = NSStackView()
        swatches.orientation = .horizontal
        swatches.spacing = 4
        for color in Self.swatchColors {
            let swatch = ColorSwatchButton(color: color)
            swatch.isSelectedSwatch = ColorSwatchButton.colorsMatch(color, editorView.effectiveStyle.color)
            swatch.target = self
            swatch.action = #selector(swatchTapped(_:))
            swatches.addArrangedSubview(swatch)
        }
        stack.addArrangedSubview(swatches)

        let style = editorView.effectiveStyle
        stack.addArrangedSubview(overflowSlider(symbol: "lineweight", tooltip: L10n.text(.strokeWidth), min: 1, max: 12, value: Double(style.strokeWidth), action: #selector(strokeChanged(_:))))
        stack.addArrangedSubview(overflowSlider(symbol: "circle.lefthalf.filled", tooltip: L10n.text(.opacity), min: 0, max: 100, value: Double(style.opacity * 100), action: #selector(opacityChanged(_:))))
        if editorView.selectedIsText {
            stack.addArrangedSubview(overflowSlider(symbol: "textformat.size", tooltip: L10n.text(.fontSize), min: 8, max: 72, value: Double(style.fontSize), action: #selector(fontSizeChanged(_:))))
        }
        if editorView.selectedIsBlur || editorView.selectedIsPixelate {
            let isBlur = editorView.selectedIsBlur
            stack.addArrangedSubview(overflowSlider(symbol: "wand.and.rays", tooltip: L10n.text(.effectStrength), min: isBlur ? 1 : 2, max: isBlur ? 50 : 40, value: Double(editorView.selectedEffectValue), action: #selector(effectChanged(_:))))
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 224),
        ])
        vc.view = container
        return vc
    }

    private func overflowSlider(symbol: String, tooltip: String, min: Double, max: Double, value: Double, action: Selector) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        icon.contentTintColor = MoliDesign.tertiaryText
        row.addArrangedSubview(icon)
        let slider = NSSlider()
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value
        slider.target = self
        slider.action = action
        slider.toolTip = tooltip
        slider.widthAnchor.constraint(equalToConstant: 168).isActive = true
        row.addArrangedSubview(slider)
        return row
    }

    /// A 1×16 hairline with 8pt breathing room on each side, used to separate
    /// toolbar groups. MoliCardView keeps the layer colour in sync with the
    /// effective appearance so the line never strands an old cgColor.
    private func toolbarSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let line = MoliCardView(fillColor: MoliDesign.hairline, cornerRadius: 0)
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 17),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 16),
            line.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func toolbarSymbol(_ symbol: String, title: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
    }

    private func configureZoomStack() {
        zoomStack.orientation = .horizontal
        zoomStack.alignment = .centerY
        zoomStack.spacing = 2
        zoomStack.translatesAutoresizingMaskIntoConstraints = false

        // Upload is rarely used — it lives in the bottom bar, not the toolbar.
        zoomStack.addArrangedSubview(zoomBarButton(symbol: "icloud.and.arrow.up", tooltip: L10n.text(.upload), action: #selector(uploadImage)))
        let gap = NSView()
        gap.translatesAutoresizingMaskIntoConstraints = false
        gap.widthAnchor.constraint(equalToConstant: 10).isActive = true
        zoomStack.addArrangedSubview(gap)

        zoomStack.addArrangedSubview(zoomBarButton(symbol: "minus.magnifyingglass", tooltip: L10n.text(.zoomOut), action: #selector(zoomOut), shortcut: "⌘−"))
        zoomLabel.alignment = .center
        zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        zoomStack.addArrangedSubview(zoomLabel)
        zoomStack.addArrangedSubview(zoomBarButton(symbol: "plus.magnifyingglass", tooltip: L10n.text(.zoomIn), action: #selector(zoomIn), shortcut: "⌘+"))
        zoomStack.addArrangedSubview(zoomBarButton(symbol: "1.magnifyingglass", tooltip: L10n.text(.actualSize), action: #selector(actualSize), shortcut: "⌘1"))
        zoomStack.addArrangedSubview(zoomBarButton(symbol: "arrow.up.left.and.arrow.down.right", tooltip: L10n.text(.fit), action: #selector(fitToWindow), shortcut: "⌘0"))
    }

    private func zoomBarButton(symbol: String, tooltip: String, action: Selector, shortcut: String? = nil) -> MoliHoverButton {
        let button = MoliHoverButton()
        button.layer?.cornerRadius = 5
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        button.imagePosition = .imageOnly
        button.toolTip = shortcut.map { "\(tooltip)  \($0)" } ?? tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
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
            let isSelected = editorView.currentTool == tool && !editorView.cropMode
            button.state = isSelected ? .on : .off
            button.isSelectedAppearance = isSelected
        }
        cropButton?.isSelectedAppearance = editorView.cropMode
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

    @objc private func swatchTapped(_ sender: ColorSwatchButton) {
        editorView.setStrokeColor(sender.swatchColor)
        colorWell.color = sender.swatchColor
        refreshSwatchSelection(current: sender.swatchColor)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        editorView.setStrokeColor(sender.color)
        refreshSwatchSelection(current: sender.color)
    }

    @objc private func strokeChanged(_ sender: NSSlider) {
        editorView.setStrokeWidth(CGFloat(sender.doubleValue))
        showSliderValue("\(L10n.text(.strokeWidth)) \(Int(sender.doubleValue.rounded()))")
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) {
        editorView.setFontSize(CGFloat(sender.doubleValue))
        showSliderValue("\(L10n.text(.fontSize)) \(Int(sender.doubleValue.rounded()))")
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        editorView.setOpacity(CGFloat(sender.doubleValue / 100))
        showSliderValue("\(L10n.text(.opacity)) \(Int(sender.doubleValue.rounded()))%")
    }

    @objc private func effectChanged(_ sender: NSSlider) {
        let v = CGFloat(sender.doubleValue)
        if editorView.selectedIsBlur {
            editorView.setBlurRadius(v)
        } else if editorView.selectedIsPixelate {
            editorView.setPixelSize(v)
        }
        showSliderValue("\(L10n.text(.effectStrength)) \(Int(v.rounded()))")
    }

    /// Briefly surface a slider's live value where the zoom % normally sits,
    /// then restore the zoom readout — the sliders otherwise give no numeric
    /// feedback while dragging.
    private func showSliderValue(_ text: String) {
        zoomLabel.stringValue = text
        sliderValueRestoreItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.zoomLabel.stringValue = "\(Int((self.scrollView.magnification * 100).rounded()))%"
        }
        sliderValueRestoreItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
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
            // Second click applies the drawn crop; with no valid rect it just
            // exits crop mode.
            if editorView.applyCropModal() {
                showTransientStatus(L10n.text(.cropApplied))
            }
        } else {
            // The persistent confirm bar replaces the transient crop hint.
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
        refreshSwatchSelection(current: style.color)
        strokeSlider.doubleValue = Double(style.strokeWidth)
        fontSizeSlider.doubleValue = Double(style.fontSize)
        opacitySlider.doubleValue = Double(style.opacity * 100)

        let isBlur = view.selectedIsBlur
        let isPixelate = view.selectedIsPixelate
        if isBlur {
            effectSlider.minValue = 1; effectSlider.maxValue = 50
            effectSlider.doubleValue = Double(view.selectedEffectValue)
        } else if isPixelate {
            effectSlider.minValue = 2; effectSlider.maxValue = 40
            effectSlider.doubleValue = Double(view.selectedEffectValue)
        }

        let supportsFill = view.selectedSupportsFill
        if supportsFill {
            let fc = view.effectiveFillColor
            fillCheckbox.state = fc == nil ? .off : .on
            fillWell.color = fc ?? view.effectiveStyle.color
        }

        setContainersHidden([
            (fontSizeContainer, !view.selectedIsText),
            (effectContainer, !(isBlur || isPixelate)),
            (fillContainer, !supportsFill),
        ])
    }

    /// Show/hide the conditional toolbar containers with a short layout
    /// animation instead of an instant jump.
    private func setContainersHidden(_ changes: [(NSView, Bool)]) {
        let dirty = changes.filter { $0.0.isHidden != $0.1 }
        guard !dirty.isEmpty else { return }
        if MoliDesign.reduceMotion {
            dirty.forEach { $0.0.isHidden = $0.1 }
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            dirty.forEach { $0.0.isHidden = $0.1 }
            toolBarView.layoutSubtreeIfNeeded()
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
        updateCropConfirmBar()
    }

    /// Show the crop confirm bar while the crop modal is active; hide it once
    /// the modal is applied or cancelled.
    private func updateCropConfirmBar() {
        if editorView.cropMode {
            showCropConfirmBar()
        } else {
            hideCropConfirmBar()
        }
    }

    private func showCropConfirmBar() {
        guard let content = window?.contentView else { return }
        let bar: CropConfirmBar
        if let existing = cropConfirmBar {
            bar = existing
        } else {
            bar = CropConfirmBar(
                applyAction: { [weak self] in
                    guard let self else { return }
                    if self.editorView.applyCropModal() {
                        self.showTransientStatus(L10n.text(.cropApplied))
                    }
                },
                cancelAction: { [weak self] in self?.editorView.cancelCropMode() }
            )
            content.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                bar.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            ])
            cropConfirmBar = bar
        }
        guard bar.isHidden || bar.alphaValue < 1 else { return }
        bar.isHidden = false
        content.layoutSubtreeIfNeeded()
        bar.animateIn()
    }

    private func hideCropConfirmBar() {
        guard let bar = cropConfirmBar, !bar.isHidden else { return }
        bar.animateOut { [weak bar] in bar?.isHidden = true }
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        MoliToast.dismiss()
        onClose(self)
    }

    func windowDidResize(_ notification: Notification) {
        recenterImageIfNeeded()
        updateStatusLabel()
        updateToolbarCollapse()
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

            // Crop modal: Return applies, Esc cancels — handled here so they
            // work regardless of which view is first responder.
            if self.editorView.cropMode {
                if event.keyCode == 36 {  // Return
                    if self.editorView.applyCropModal() {
                        self.showTransientStatus(L10n.text(.cropApplied))
                    }
                    return nil
                }
                if event.keyCode == 53 {  // Esc
                    self.editorView.cancelCropMode()
                    return nil
                }
            }

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
                        return nil
                    }
                    return event  // no annotation data on the pasteboard
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

            // Single-key tool switching (no modifiers). Disabled in crop modal
            // (those keys would conflict with crop interactions). Text-editing
            // is already passed through above.
            if flags.isEmpty && !self.editorView.cropMode {
                if let key = event.charactersIgnoringModifiers?.lowercased(),
                   let tool = Self.toolShortcut[key] {
                    self.editorView.commitActiveTextEditing()
                    self.editorView.currentTool = tool
                    self.refreshToolButtons()
                    self.updateStatusLabel(tool: tool)
                    return nil
                }
            }

            return event
        }
    }

    /// Reverse of `AnnotationTool.shortcutKey` — the single source of truth for
    /// tool shortcuts lives on the tool itself, so tooltip and key handling agree.
    private static let toolShortcut: [String: AnnotationTool] = {
        var map: [String: AnnotationTool] = [:]
        for tool in AnnotationTool.allCases {
            if let key = tool.shortcutKey { map[key.lowercased()] = tool }
        }
        return map
    }()

    private func changeZoom(by factor: CGFloat) {
        let next = scrollView.magnification * factor
        setZoom(next, centerAt: visibleCenter())
    }

    private func setZoom(_ value: CGFloat, centerAt center: NSPoint, animated: Bool = true) {
        let clamped = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        if animated && !MoliDesign.reduceMotion {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                scrollView.animator().setMagnification(clamped, centeredAt: center)
            }, completionHandler: { [weak self] in
                self?.recenterImageIfNeeded()
                self?.updateStatusLabel()
            })
            zoomLabel.stringValue = "\(Int((clamped * 100).rounded()))%"
        } else {
            scrollView.setMagnification(clamped, centeredAt: center)
            recenterImageIfNeeded()
            updateStatusLabel()
        }
    }

    private func zoomToFit(animated: Bool = true) {
        let visibleSize = scrollView.contentSize
        let imageSize = editorView.effectiveSize
        guard visibleSize.width > 0, visibleSize.height > 0, imageSize.width > 0, imageSize.height > 0 else { return }
        let widthFit = visibleSize.width / imageSize.width
        let heightFit = visibleSize.height / imageSize.height
        // Never scale up past 1:1 — small captures display at their natural
        // size; only larger-than-window images are scaled down to fit.
        let target = min(widthFit, heightFit, 1)
        setZoom(target, centerAt: NSPoint(x: imageSize.width / 2, y: imageSize.height / 2), animated: animated)
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
        _ = tool
        let pointSize = editorView.effectiveSize
        let fullPoint = editorView.baseImage.size
        let fullPixel = editorView.baseImage.pixelSize ?? fullPoint
        let scaleX = fullPoint.width > 0 ? fullPixel.width / fullPoint.width : 1
        let scaleY = fullPoint.height > 0 ? fullPixel.height / fullPoint.height : 1
        let pixelSize = NSSize(width: pointSize.width * scaleX, height: pointSize.height * scaleY)
        // Only export pixels matter to the user; pt/px double-display was an
        // engineer's view.
        statusLabel.stringValue = "\(Int(pixelSize.width))×\(Int(pixelSize.height)) px  ·  \(editorView.annotations.count) \(L10n.text(.annotations))"
        zoomLabel.stringValue = "\(Int((scrollView.magnification * 100).rounded()))%"
    }

    @objc private func languageDidChange() {
        configureToolbar()
        updateStatusLabel()
        DispatchQueue.main.async { [weak self] in self?.updateToolbarCollapse() }
    }

    /// Transient feedback now surfaces as a HUD toast over the canvas instead
    /// of replacing the status bar text. `autoClear: false` keeps the toast up
    /// until the next message replaces it (e.g. "Uploading…" → "Uploaded").
    private func showTransientStatus(_ message: String, duration: TimeInterval = 2.2, autoClear: Bool = true) {
        guard let host = window?.contentView else { return }
        MoliToast.show(message, in: host, duration: autoClear ? duration : 3600)
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
