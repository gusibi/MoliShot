import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate, EditorViewDelegate, NSToolbarDelegate, NSToolbarItemValidation {

    private let editorView: EditorView
    private let onClose: (EditorWindowController) -> Void
    private let onAddToShelf: (NSImage) throws -> Void

    private let scrollView = NSScrollView()
    private let clipView = CenteringClipView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    /// Bottom glass bar: style controls + status + image actions + zoom.
    /// Style lives here (not the top bar) so narrow windows only need to fit
    /// the tool row up top.
    private let bottomBarView = NSVisualEffectView()
    private let bottomStack = NSStackView()
    private let outputGroup = NSStackView()
    private var cropConfirmBar: CropConfirmBar?
    private var overflowButton: NSButton?
    /// Collapsible color and stroke controls; narrow windows use a native popover.
    private var styleGroup: NSView?
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

    init(image: NSImage, title: String,
         onAddToShelf: @escaping (NSImage) throws -> Void = { try AppCoordinator.shared.addToShelf($0) },
         onClose: @escaping (EditorWindowController) -> Void) {
        self.editorView = EditorView(image: image)
        self.onClose = onClose
        self.onAddToShelf = onAddToShelf
        self.lastImageSize = image.size

        let size = EditorWindowController.fitSize(for: image.size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Real title (Window menu, tabbing, VoiceOver); visually hidden so the
        // glass toolbar keeps its full-bleed look.
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 700, height: 420)
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

    /// Window size that wraps the image tightly at its own aspect ratio:
    /// 1:1 when it fits on screen, scaled down (aspect preserved) when not.
    /// The window hugs the picture instead of forcing a fixed chrome box.
    private static func fitSize(for imageSize: NSSize) -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1400, height: 900)
        let chromeH: CGFloat = 56 + 52 // native toolbar + control bar (approx)
        let margin: CGFloat = 60
        let availW = max(320, visible.width - margin)
        let availH = max(200, visible.height - chromeH - margin)
        let zoom = min(1, availW / imageSize.width, availH / imageSize.height)
        let w = max(700, (imageSize.width * zoom).rounded())
        let h = max(360, (imageSize.height * zoom).rounded() + chromeH)
        return NSSize(width: min(w, visible.width), height: min(h, visible.height))
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        configureToolbar()

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
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        zoomLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        zoomLabel.textColor = MoliDesign.secondaryText
        zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true

        bottomBarView.material = .headerView
        bottomBarView.blendingMode = .withinWindow
        bottomBarView.state = .active
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.orientation = .horizontal
        bottomStack.alignment = .centerY
        bottomStack.spacing = 8
        bottomStack.detachesHiddenViews = true
        bottomStack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        EditorChrome.install(bottomStack, in: bottomBarView, fallback: .headerView)

        content.addSubview(scrollView)
        content.addSubview(bottomBarView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),

            bottomBarView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

        ])

        updateStatusLabel()
        DispatchQueue.main.async { [weak self] in
            self?.fitWindowToImage(animated: false)
            self?.installEventMonitor()
            self?.updateStyleCollapse()
        }
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "MoliShot.Editor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
        configureZoomStack()
        buildBottomBar()
        refreshToolButtons()
        syncStyleControls(to: editorView)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        AnnotationTool.allCases.map { NSToolbarItem.Identifier($0.rawValue) } + [
            .flexibleSpace, .init("editor.undo"), .init("editor.redo"), .space,
            .init("editor.copy"), .init("editor.pin"), .init("editor.save")
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        AnnotationTool.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        item.isBordered = true
        if let tool = AnnotationTool(rawValue: identifier.rawValue) {
            item.label = tool.title
            item.image = toolbarSymbol(tool.symbol, title: tool.title)
            item.toolTip = tool.shortcutKey.map { "\(tool.title)  \($0)" } ?? tool.title
            item.action = tool == .crop ? #selector(toggleCropMode) : #selector(toolbarToolTapped(_:))
            item.visibilityPriority = [.select, .arrow, .rectangle, .text].contains(tool) ? .high : .standard
            return item
        }
        let title: String
        let symbol: String
        switch identifier.rawValue {
        case "editor.copy":
            title = L10n.text(.copy); symbol = "doc.on.doc"; item.action = #selector(copyImage)
            item.toolTip = title + "  ⌘C"
            item.visibilityPriority = .high
            if #available(macOS 26, *) { item.style = .prominent }
        case "editor.pin":
            title = L10n.text(.pin); symbol = "pin"; item.action = #selector(pinImage)
        case "editor.save":
            title = L10n.text(.save); symbol = "square.and.arrow.down"; item.action = #selector(saveImage)
            item.toolTip = title + "  ⌘S"
            item.visibilityPriority = .high
        case "editor.undo":
            title = L10n.text(.undo); symbol = "arrow.uturn.backward"; item.action = #selector(undoTap)
            item.toolTip = title + "  ⌘Z"
        case "editor.redo":
            title = L10n.text(.redo); symbol = "arrow.uturn.forward"; item.action = #selector(redoTap)
            item.toolTip = title + "  ⇧⌘Z"
        default: return nil
        }
        item.label = title
        item.image = toolbarSymbol(symbol, title: title)
        if item.toolTip == nil { item.toolTip = title }
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier.rawValue {
        case "editor.undo": return editorView.canUndo
        case "editor.redo": return editorView.canRedo
        default: return true
        }
    }

    /// Bottom bar: style controls (left), status (flexible middle), image
    /// actions + zoom (right). Style lives here so the top bar only needs to
    /// fit the tool row, and narrow windows collapse style into the `…`
    /// popover instead of forcing a wide window.
    private func buildBottomBar() {
        bottomStack.arrangedSubviews.forEach {
            bottomStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        bottomStack.addArrangedSubview(buildStyleGroup())

        // Overflow entry — reveals the collapsed style controls; hidden until
        // the bar actually collapses (see updateStyleCollapse).
        let overflow = compactToolbarButton(title: L10n.text(.more), symbol: "ellipsis", action: #selector(showOverflowPopover(_:)))
        overflow.isHidden = true
        overflowButton = overflow
        bottomStack.addArrangedSubview(overflow)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomStack.addArrangedSubview(spacer)

        bottomStack.addArrangedSubview(statusLabel)

        // Image actions sit with zoom: they act on the whole picture.
        outputGroup.orientation = .horizontal
        outputGroup.alignment = .centerY
        outputGroup.spacing = 8
        outputGroup.detachesHiddenViews = true
        outputGroup.arrangedSubviews.forEach {
            outputGroup.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        outputGroup.addArrangedSubview(compactToolbarButton(title: ShelfText.add, symbol: "tray.and.arrow.down", action: #selector(addToShelf(_:)), shortcut: "⌘↩"))
        outputGroup.addArrangedSubview(compactToolbarButton(title: L10n.text(.clear), symbol: "trash", action: #selector(clearTap)))
        outputGroup.addArrangedSubview(compactToolbarButton(title: L10n.text(.ocr), symbol: "text.viewfinder", action: #selector(runOCR)))
        bottomStack.addArrangedSubview(outputGroup)

        bottomStack.addArrangedSubview(zoomStack)

        styleCollapsed = false
    }

    /// Build the collapsible style group: swatch palette, stroke/opacity sliders,
    /// and the contextual font-size / effect / fill containers.
    private func buildStyleGroup() -> NSView {
        let group = NSStackView()
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = 8
        group.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
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

        fillWell.colorWellStyle = .minimal
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

        let surface = EditorChrome.styleGroup(group)
        styleGroup = surface
        return surface
    }

    private func compactToolbarButton(title: String, symbol: String, action: Selector, shortcut: String? = nil) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.controlSize = .regular
        EditorChrome.style(button)
        button.image = toolbarSymbol(symbol, title: title)
        button.imagePosition = .imageOnly
        // Tooltip surfaces the shortcut ("Rectangle  R"); the accessibility
        // label stays name-only so VoiceOver doesn't read symbol glyphs.
        button.toolTip = shortcut.map { "\(title)  \($0)" } ?? title
        button.setAccessibilityLabel(title)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
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
            swatch.toolTip = color.hexString
            swatch.setAccessibilityLabel(color.hexString)
            colorSwatches.append(swatch)
            stack.addArrangedSubview(swatch)
        }
        colorWell.colorWellStyle = .minimal
        colorWell.controlSize = .regular
        colorWell.color = editorView.strokeColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.toolTip = customColorTitle
        colorWell.setAccessibilityLabel(customColorTitle)
        stack.addArrangedSubview(colorWell)
        refreshSwatchSelection(current: editorView.effectiveStyle.color)
        return stack
    }

    private func refreshSwatchSelection(current: NSColor) {
        for swatch in colorSwatches {
            swatch.isSelectedSwatch = ColorSwatchButton.colorsMatch(swatch.swatchColor, current)
        }
    }

    private var customColorTitle: String {
        L10n.isChinese ? "自定义颜色" : "Custom Color"
    }

    /// Collapse the bottom-bar style group into the overflow popover when its
    /// natural content width exceeds the space available (with a little
    /// hysteresis so it doesn't flicker at the threshold). The reserve keeps
    /// room for status text, the output group, and zoom at the right end.
    private func updateStyleCollapse() {
        guard bottomBarView.bounds.width > 0, let styleGroup else { return }
        let reserve = outputGroup.fittingSize.width + zoomStack.fittingSize.width + 170
        let available = bottomBarView.bounds.width - reserve
        if styleCollapsed {
            if available >= lastExpandedWidth + 30 { setStyleCollapsed(false) }
        } else {
            lastExpandedWidth = styleGroup.fittingSize.width
            if available < lastExpandedWidth { setStyleCollapsed(true) }
        }
    }

    private func setStyleCollapsed(_ collapsed: Bool) {
        styleCollapsed = collapsed
        styleGroup?.isHidden = collapsed
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
            swatch.toolTip = color.hexString
            swatch.setAccessibilityLabel(color.hexString)
            swatches.addArrangedSubview(swatch)
        }
        let customWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        customWell.colorWellStyle = .minimal
        customWell.color = editorView.effectiveStyle.color
        customWell.target = self
        customWell.action = #selector(colorChanged(_:))
        customWell.toolTip = customColorTitle
        customWell.setAccessibilityLabel(customColorTitle)
        swatches.addArrangedSubview(customWell)
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

    private func toolbarSymbol(_ symbol: String, title: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
    }

    private func configureZoomStack() {
        zoomStack.arrangedSubviews.forEach {
            zoomStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
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
        zoomStack.addArrangedSubview(zoomLabel)
        zoomStack.addArrangedSubview(zoomBarButton(symbol: "plus.magnifyingglass", tooltip: L10n.text(.zoomIn), action: #selector(zoomIn), shortcut: "⌘+"))
        zoomStack.addArrangedSubview(zoomBarButton(symbol: "1.magnifyingglass", tooltip: L10n.text(.actualSize), action: #selector(actualSize), shortcut: "⌘1"))
        zoomStack.addArrangedSubview(zoomBarButton(symbol: "arrow.up.left.and.arrow.down.right", tooltip: L10n.text(.fit), action: #selector(fitToWindow), shortcut: "⌘0"))
    }

    private func zoomBarButton(symbol: String, tooltip: String, action: Selector, shortcut: String? = nil) -> NSButton {
        let button = NSButton()
        button.title = ""
        EditorChrome.style(button)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        button.imagePosition = .imageOnly
        button.toolTip = shortcut.map { "\(tooltip)  \($0)" } ?? tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
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
        let selected = editorView.cropMode ? AnnotationTool.crop : editorView.currentTool
        window?.toolbar?.selectedItemIdentifier = .init(selected.rawValue)
        window?.toolbar?.validateVisibleItems()
    }

    // MARK: - Toolbar actions

    @objc private func toolbarToolTapped(_ sender: NSToolbarItem) {
        guard let tool = AnnotationTool(rawValue: sender.itemIdentifier.rawValue) else { return }
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


    // MARK: - Main-menu actions (responder chain)

    /// The local key monitor consumes the keyboard equivalents, so these
    /// primarily serve menu clicks — and the menus serve discovery. An
    /// editing text field sits earlier in the chain and keeps its native
    /// cut/copy/paste behaviour.
    @objc func undo(_ sender: Any?) { undoTap() }
    @objc func redo(_ sender: Any?) { redoTap() }
    @objc func cut(_ sender: Any?) {
        guard editorView.hasSelection else { NSSound.beep(); return }
        _ = editorView.copySelection()
        _ = editorView.deleteSelection()
        showTransientStatus(L10n.text(.copiedToClipboard))
    }
    @objc func copy(_ sender: Any?) { performCopy() }
    @objc func paste(_ sender: Any?) {
        if editorView.paste() {
            showTransientStatus(L10n.text(.pastedAnnotation))
        } else {
            NSSound.beep()
        }
    }
    @objc func delete(_ sender: Any?) {
        if !editorView.deleteSelection() { NSSound.beep() }
    }
    @objc func saveDocument(_ sender: Any?) { saveImage() }
    @objc func menuZoomIn(_ sender: Any?) { zoomIn() }
    @objc func menuZoomOut(_ sender: Any?) { zoomOut() }
    @objc func menuActualSize(_ sender: Any?) { actualSize() }
    @objc func menuFitToWindow(_ sender: Any?) { fitToWindow() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return editorView.canUndo
        case #selector(redo(_:)): return editorView.canRedo
        case #selector(cut(_:)), #selector(delete(_:)): return editorView.hasSelection
        case #selector(paste(_:)):
            return NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(AnnotationClipboard.uti)) != nil
        default: return true
        }
    }

    private func performCopy() {
        if editorView.hasSelection {
            _ = editorView.copySelection()
            showTransientStatus(L10n.text(.copiedToClipboard))
        } else {
            copyImage()
        }
    }

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
        AppCoordinator.shared.recognizeText(in: editorView.renderFinalImage())
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

    @objc func addToShelf(_ sender: Any?) {
        // A pending crop must be resolved before taking the final snapshot.
        if editorView.cropMode, !editorView.applyCropModal() { return }
        do {
            try onAddToShelf(editorView.renderFinalImage())
            close()
        } catch {
            showTransientStatus(error.localizedDescription, duration: 4)
        }
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
            bottomBarView.layoutSubtreeIfNeeded()
        }
    }
    func editorViewDidChangeContent(_ view: EditorView) {
        if !lastImageSize.equalTo(view.effectiveSize) {
            lastImageSize = view.effectiveSize
            fitWindowToImage()
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
        updateStyleCollapse()
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
                case "z", "Z":
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
                    self.performCopy()
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

    /// Resize the window so its viewport wraps the image tightly at its own
    /// aspect ratio (1:1 when it fits on screen, scaled down otherwise).
    /// Called on open and whenever the effective image size changes (crop).
    /// The ⌘0 "fit" action only adjusts zoom and leaves the window alone.
    private func fitWindowToImage(animated: Bool = true) {
        guard let window else { return }
        let imageSize = editorView.effectiveSize
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        // Live chrome delta: window size minus the scroll viewport.
        let chrome = NSSize(width: window.frame.width - scrollView.contentSize.width,
                            height: window.frame.height - scrollView.contentSize.height)
        let margin: CGFloat = 40
        let availW = max(320, visible.width - chrome.width - margin)
        let availH = max(200, visible.height - chrome.height - margin)
        let zoom = min(1, availW / imageSize.width, availH / imageSize.height)
        var winW = imageSize.width * zoom + chrome.width
        var winH = imageSize.height * zoom + chrome.height
        winW = min(max(winW, window.minSize.width), visible.width)
        winH = min(max(winH, window.minSize.height), visible.height)
        var frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = NSSize(width: winW, height: winH)
        frame.origin = NSPoint(x: center.x - winW / 2, y: center.y - winH / 2)
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - winW }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - winH }
        window.setFrame(frame, display: true, animate: animated && !MoliDesign.reduceMotion)
        updateStyleCollapse()
        setZoom(zoom, centerAt: NSPoint(x: imageSize.width / 2, y: imageSize.height / 2), animated: false)
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
        DispatchQueue.main.async { [weak self] in self?.updateStyleCollapse() }
    }

    /// Non-modal notice surfaced as a HUD toast over the canvas. Used for
    /// post-capture notices (e.g. the accessibility hint) that must not
    /// steal focus or block the capture flow with a modal dialog.
    func showNotice(_ message: String) {
        showTransientStatus(message, duration: 4)
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
