import AppKit
import Quartz

final class ScreenshotShelfWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout,
    QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    private let store: ScreenshotShelfStore
    private let pasteboard: NSPasteboard
    private let onCapture: () -> Void
    private let collection = ShelfCollectionView()
    private let scroll = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let captureButton = NSButton()
    private let moreButton = NSButton()
    private let collapseButton = NSButton()
    private let dragButton = ShelfDragButton()
    private let clearButton = NSButton()
    private let hintLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private let footer = NSStackView()
    private var collapsed = false
    private var feedbackReset: DispatchWorkItem?
    private static let dragType = NSPasteboard.PasteboardType("com.molishot.shelf-entry")

    init(store: ScreenshotShelfStore = .shared, pasteboard: NSPasteboard = .general, onCapture: @escaping () -> Void) {
        self.store = store
        self.pasteboard = pasteboard
        self.onCapture = onCapture
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 252),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
                                          y: screen.visibleFrame.minY + 32))
        }
        panel.setFrameUsingName("ScreenshotShelf")
        panel.setFrameAutosaveName("ScreenshotShelf")
        super.init(window: panel)
        panel.delegate = self
        setupUI()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged(_:)), name: ScreenshotShelfStore.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .appLanguageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit {
        feedbackReset?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func present() {
        guard let window else { return }
        if !window.isVisible {
            if window.frame.origin == .zero, let screen = NSScreen.main {
                window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                                              y: screen.visibleFrame.minY + 32))
            }
            keepOnScreen()
        }
        window.orderFrontRegardless()
    }

    private func setupUI() {
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        window?.contentView = material

        countLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let heading = NSStackView(views: [countLabel, statusLabel])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        heading.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configure(captureButton, symbol: "viewfinder", action: #selector(captureNext))
        configure(copyButton, symbol: "doc.on.doc", action: #selector(copyAll))
        copyButton.bezelColor = .controlAccentColor
        if #available(macOS 26, *) { copyButton.tintProminence = .primary }
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = .command
        configure(moreButton, symbol: "ellipsis", action: #selector(showSharingMenu(_:)))
        moreButton.setAccessibilityLabel(ShelfText.text("更多分享方式", "More sharing options"))
        let header = NSStackView(views: [heading, captureButton, copyButton, moreButton])
        header.distribution = .fill
        header.alignment = .centerY
        header.spacing = 8

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 146, height: 116)
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.backgroundColors = [.clear]
        collection.register(ShelfItem.self, forItemWithIdentifier: .init("shelf"))
        collection.registerForDraggedTypes([Self.dragType])
        collection.setDraggingSourceOperationMask(.move, forLocal: true)
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.onPreview = { [weak self] in self?.preview() }
        collection.onDelete = { [weak self] in self?.removeSelected() }
        collection.onMove = { [weak self] delta in self?.moveSelected(by: delta) }
        collection.makeMenu = { [weak self] in self?.itemMenu() }
        scroll.documentView = collection
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        configure(dragButton, symbol: "hand.draw", action: #selector(explainDrag))
        dragButton.payload = { [weak self] in
            guard let self else { return [] }
            return self.store.entries.map { (self.store.url(for: $0), self.store.thumbnail(for: $0)) }
        }
        configure(collapseButton, symbol: "chevron.down", action: #selector(toggleCollapsed))
        configure(clearButton, symbol: "trash", action: #selector(clearShelf))
        footer.setViews([clearButton, hintLabel, spacer, dragButton, collapseButton], in: .leading)
        footer.alignment = .centerY
        footer.spacing = 8
        let stack = NSStackView(views: [header, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let chromeHost: NSView
        if #available(macOS 26, *) {
            // Batch the native glass controls without making the screenshots glass.
            // Keep content inside contentView so AppKit owns composition and contrast.
            let container = NSGlassEffectContainerView()
            container.spacing = 0
            container.contentView = stack
            container.translatesAutoresizingMaskIntoConstraints = false
            chromeHost = container
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                stack.topAnchor.constraint(equalTo: container.topAnchor),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            chromeHost = stack
        }
        material.addSubview(chromeHost)
        NSLayoutConstraint.activate([
            chromeHost.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 18),
            chromeHost.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -18),
            chromeHost.topAnchor.constraint(equalTo: material.topAnchor, constant: 14),
            chromeHost.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -14),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func configure(_ button: NSButton, symbol: String, action: Selector) {
        button.title = ""
        if #available(macOS 26, *) {
            button.bezelStyle = .glass
            button.borderShape = .circle
            button.tintProminence = .none
        } else {
            button.bezelStyle = .circular
        }
        button.image = actionSymbol(symbol)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func actionSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
    }

    @objc private func storeChanged(_ notification: Notification) {
        guard notification.object as? ScreenshotShelfStore === store else { return }
        refresh()
    }

    @objc private func languageChanged() { refresh() }

    private func refresh() {
        feedbackReset?.cancel()
        window?.title = ShelfText.title
        countLabel.stringValue = ShelfText.count(store.entries.count)
        moreButton.setAccessibilityLabel(ShelfText.text("更多分享方式", "More sharing options"))
        moreButton.toolTip = ShelfText.text("更多分享方式", "More sharing options")
        statusLabel.stringValue = store.entries.isEmpty ? ShelfText.emptyHint : ShelfText.ready
        for (button, label) in [(captureButton, ShelfText.capture), (copyButton, ShelfText.copy),
                                (dragButton, ShelfText.drag), (clearButton, ShelfText.clear),
                                (collapseButton, collapsed ? ShelfText.expand : ShelfText.collapse)] {
            button.title = ""
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }
        copyButton.toolTip = ShelfText.copy + "  ⌘C\n" + ShelfText.text("复制全部 PNG 图片文件，适合粘贴到 Codex 等附件输入框", "Copy all PNG files for attachment fields such as Codex")
        copyButton.isEnabled = !store.entries.isEmpty
        copyButton.image = actionSymbol("doc.on.doc")
        dragButton.isEnabled = !store.entries.isEmpty
        clearButton.isEnabled = !store.entries.isEmpty
        dragButton.toolTip = ShelfText.drag + "\n" + ShelfText.text("按住并拖到目标应用，发送全部图片文件", "Drag this button to another app to attach every image file")
        hintLabel.stringValue = ShelfText.hint
        emptyLabel.stringValue = ShelfText.empty
        emptyLabel.isHidden = !store.entries.isEmpty
        collapseButton.image = actionSymbol(collapsed ? "chevron.up" : "chevron.down")
        rebuildMenu()
        collection.reloadData()
        if !store.entries.isEmpty {
            collection.selectItems(at: [IndexPath(item: store.entries.count - 1, section: 0)], scrollPosition: .right)
        }
        if ownsPreview { QLPreviewPanel.shared()?.reloadData() }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for (label, symbol, action) in [(ShelfText.copyImages, "photo.on.rectangle", #selector(copyImages)),
                                        (ShelfText.merge, "rectangle.portrait", #selector(copyMerged))] {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = self
            item.isEnabled = !store.entries.isEmpty
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: collapsed ? ShelfText.expand : ShelfText.collapse, action: #selector(toggleCollapsed), keyEquivalent: "")
        toggle.image = actionSymbol(collapsed ? "chevron.up" : "chevron.down")
        toggle.target = self
        menu.addItem(toggle)
        menu.autoenablesItems = false
        moreButton.menu = menu
    }

    @objc private func showSharingMenu(_ sender: NSButton) {
        sender.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 6), in: sender)
    }

    @objc private func captureNext() { onCapture() }
    @objc func copy(_ sender: Any?) { export(.files) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)): return !store.entries.isEmpty
        case #selector(moveEarlier): return selectedEntry != nil && selectedEntry != store.entries.first
        case #selector(moveLater): return selectedEntry != nil && selectedEntry != store.entries.last
        default: return true
        }
    }
    @objc private func copyAll() { export(.files) }
    @objc private func copyImages() { export(.images) }
    @objc private func copyMerged() { export(.merged) }

    private func export(_ format: ShelfExport) {
        do {
            try store.copy(format, to: pasteboard)
            statusLabel.stringValue = ShelfText.copied(store.entries.count, format: format)
            copyButton.image = actionSymbol("checkmark")
            feedbackReset?.cancel()
            let reset = DispatchWorkItem { [weak self] in
                self?.copyButton.image = self?.actionSymbol("doc.on.doc")
            }
            feedbackReset = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = ShelfText.failure
        alert.informativeText = error.localizedDescription
        if let window { alert.beginSheetModal(for: window) }
    }

    @objc private func explainDrag() {
        statusLabel.stringValue = ShelfText.text("按住手形图标，拖到目标应用的输入框。", "Hold the hand icon and drag it into the destination app.")
    }

    @objc private func toggleCollapsed() {
        guard let window else { return }
        collapsed.toggle()
        scroll.isHidden = collapsed
        footer.isHidden = collapsed
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: 680, height: collapsed ? 66 : 252))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        refresh()
        keepOnScreen()
    }

    @objc private func screensChanged() { keepOnScreen() }
    private func keepOnScreen() {
        guard let window, let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(window.frame) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: max(frame.minX, min(window.frame.minX, frame.maxX - window.frame.width)),
                                      y: max(frame.minY, min(window.frame.minY, frame.maxY - window.frame.height))))
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { store.entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("shelf"), for: indexPath) as! ShelfItem
        let entry = store.entries[indexPath.item]
        item.configure(image: store.thumbnail(for: entry), number: indexPath.item + 1,
                       dimensions: "\(entry.pixelWidth) × \(entry.pixelHeight)")
        item.onRemove = { [weak self] in self?.remove(id: entry.id) }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let entry = store.entries[indexPath.item]
        let item = NSPasteboardItem()
        item.setString(entry.id.uuidString, forType: Self.dragType)
        item.setString(store.url(for: entry).absoluteString, forType: .fileURL)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard draggingInfo.draggingSource as? NSCollectionView === collectionView else { return [] }
        proposedDropOperation.pointee = .before
        return .move
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard draggingInfo.draggingSource as? NSCollectionView === collectionView,
              let value = draggingInfo.draggingPasteboard.string(forType: Self.dragType),
              let id = UUID(uuidString: value), let source = store.entries.firstIndex(where: { $0.id == id }) else { return false }
        do {
            try store.move(id: id, to: indexPath.item > source ? indexPath.item - 1 : indexPath.item)
            select(id: id)
            return true
        } catch { showError(error); return false }
    }

    private var selectedEntry: ShelfEntry? {
        guard let index = collection.selectionIndexPaths.first?.item, store.entries.indices.contains(index) else { return nil }
        return store.entries[index]
    }

    private func select(id: UUID) {
        if let index = store.entries.firstIndex(where: { $0.id == id }) {
            collection.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestHorizontalEdge)
        }
    }

    @objc private func removeSelected() {
        guard let entry = selectedEntry else { return }
        remove(id: entry.id)
    }
    private func remove(id: UUID) {
        do { try store.remove(id: id) } catch { showError(error) }
    }
    @objc private func clearShelf() {
        do { try store.removeAll() } catch { showError(error) }
    }
    @objc private func moveEarlier() { moveSelected(by: -1) }
    @objc private func moveLater() { moveSelected(by: 1) }
    private func moveSelected(by delta: Int) {
        guard let entry = selectedEntry, let source = store.entries.firstIndex(of: entry) else { return }
        do { try store.move(id: entry.id, to: source + delta); select(id: entry.id) } catch { showError(error) }
    }

    private func itemMenu() -> NSMenu {
        let menu = NSMenu()
        for (label, action) in [(ShelfText.preview, #selector(preview)), (ShelfText.earlier, #selector(moveEarlier)),
                                (ShelfText.later, #selector(moveLater)), (ShelfText.remove, #selector(removeSelected))] {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    private var ownsPreview: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.dataSource === self
    }

    var previewWindow: NSWindow? { ownsPreview ? QLPreviewPanel.shared() : nil }
    func windowWillClose(_ notification: Notification) {
        if ownsPreview { QLPreviewPanel.shared()?.orderOut(nil) }
    }
    @objc private func preview() {
        guard !store.entries.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if ownsPreview && panel.isVisible { panel.orderOut(nil); return }
        window?.makeKey()
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = collection.selectionIndexPaths.first?.item ?? 0
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { store.entries.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard store.entries.indices.contains(index) else { return nil }
        return store.url(for: store.entries[index]) as NSURL
    }
}

private final class ShelfCollectionView: NSCollectionView {
    var onPreview: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var makeMenu: (() -> NSMenu?)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            if event.keyCode == 49 { onPreview?(); return }
            if event.keyCode == 51 { onDelete?(); return }
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if event.keyCode == 123 { onMove?(-1); return }
            if event.keyCode == 124 { onMove?(1); return }
        }
        super.keyDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 { onPreview?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        selectItems(at: [index], scrollPosition: [])
        return makeMenu?()
    }
}

private final class ShelfItem: NSCollectionViewItem {
    private let thumbnail = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    var onRemove: (() -> Void)?
    override var isSelected: Bool { didSet { (view as? ShelfCard)?.selected = isSelected } }
    override func loadView() {
        view = ShelfCard()
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        caption.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        if #available(macOS 26, *) {
            removeButton.bezelStyle = .glass
            removeButton.borderShape = .circle
            removeButton.tintProminence = .none
        } else {
            removeButton.bezelStyle = .circular
        }
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        removeButton.imagePosition = .imageOnly
        removeButton.target = self
        removeButton.action = #selector(removeItem)
        for child in [thumbnail, caption, removeButton] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            removeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            removeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            removeButton.widthAnchor.constraint(equalToConstant: 22),
            removeButton.heightAnchor.constraint(equalToConstant: 22),
            thumbnail.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            thumbnail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            thumbnail.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            thumbnail.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -5),
            caption.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            caption.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            caption.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            caption.heightAnchor.constraint(equalToConstant: 14)
        ])
    }
    func configure(image: NSImage?, number: Int, dimensions: String) {
        thumbnail.image = image
        caption.stringValue = "\(number)  ·  \(dimensions)"
        removeButton.toolTip = ShelfText.remove
        removeButton.setAccessibilityLabel(ShelfText.text("移除第 \(number) 张截图", "Remove screenshot \(number)"))
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityChildren([removeButton])
        view.setAccessibilityLabel(ShelfText.text("截图 \(number)，\(dimensions) 像素", "Screenshot \(number), \(dimensions) pixels"))
        view.toolTip = ShelfText.preview
        (view as? ShelfCard)?.selected = isSelected
    }
    @objc private func removeItem() { onRemove?() }
}

private final class ShelfCard: NSView {
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        NSColor.controlBackgroundColor.withAlphaComponent(0.7).setFill()
        path.fill()
        (selected ? NSColor.controlAccentColor : .separatorColor).setStroke()
        path.lineWidth = selected ? 2 : 0.5
        path.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

private final class ShelfDragButton: NSButton, NSDraggingSource {
    var payload: (() -> [(URL, NSImage?)])?
    private var press: NSPoint?
    private var dragging = false
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        press = event.locationInWindow
        dragging = false
        highlight(true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, !dragging, let press,
              hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) > 4,
              let files = payload?(), !files.isEmpty else { return }
        dragging = true
        highlight(false)
        let items = files.enumerated().map { index, file -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: file.0 as NSURL)
            item.setDraggingFrame(NSRect(x: CGFloat(index % 4) * 6, y: CGFloat(index % 4) * 6, width: 96, height: 72),
                                  contents: file.1 ?? NSWorkspace.shared.icon(forFile: file.0.path))
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }
    override func mouseUp(with event: NSEvent) {
        highlight(false)
        if !dragging, isEnabled, let action { sendAction(action, to: target) }
        press = nil
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
