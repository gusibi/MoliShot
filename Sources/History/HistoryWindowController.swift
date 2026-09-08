import AppKit
import Quartz

final class HistoryWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate {

    private let collectionView = NSCollectionView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: L10n.text(.noScreenshotsYet))
    private let emptyStack = NSStackView()
    private var spaceMonitor: Any?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.history)
        window.center()
        super.init(window: window)

        HistoryStore.shared.onChange = { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil)
        setupUI()
        reload()
        // Space toggles Quick Look, Finder-style. The panel is a separate
        // key window, so this monitor naturally goes quiet while it is open.
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, event.keyCode == 49 else { return event }
            self.toggleQuickLook()
            return nil
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let spaceMonitor { NSEvent.removeMonitor(spaceMonitor) }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        window?.backgroundColor = MoliDesign.canvas

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 210, height: 164)
        layout.sectionInset = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 14
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.register(HistoryCell.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("cell"))
        collectionView.backgroundColors = [MoliDesign.canvas]

        scroll.documentView = collectionView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        let emptyIcon = NSImageView()
        emptyIcon.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 44, weight: .light))
        emptyIcon.contentTintColor = MoliDesign.tertiaryText

        emptyLabel.textColor = MoliDesign.secondaryText
        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 12
        emptyStack.addArrangedSubview(emptyIcon)
        emptyStack.addArrangedSubview(emptyLabel)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyStack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    private func reload() {
        window?.title = L10n.text(.history)
        emptyLabel.stringValue = L10n.text(.noScreenshotsYet)
        emptyStack.isHidden = !HistoryStore.shared.entries.isEmpty
        collectionView.reloadData()
    }

    @objc private func languageDidChange() {
        reload()
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        HistoryStore.shared.entries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("cell"), for: indexPath) as! HistoryCell
        let entry = HistoryStore.shared.entries[indexPath.item]
        item.configure(with: entry)
        item.onOpen = { [weak self] in
            guard let self = self, let image = HistoryStore.shared.image(for: entry) else { return }
            AppCoordinator.shared.openEditor(with: image, title: AppCoordinator.screenshotTitle(for: entry.timestamp))
            _ = self
        }
        item.onDelete = { HistoryStore.shared.delete(entry) }
        item.onCopyImage = {
            if let image = HistoryStore.shared.image(for: entry) {
                NSPasteboard.general.writeImage(image)
            }
        }
        item.onReveal = {
            let url = entry.url(in: HistoryStore.shared.directory)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        item.onRightClick = { [weak self] in
            self?.collectionView.deselectAll(nil)
            self?.collectionView.selectItems(at: [indexPath], scrollPosition: [])
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true {
            QLPreviewPanel.shared()?.reloadData()
        }
    }

    // MARK: - Quick Look

    private func toggleQuickLook() {
        guard previewURL() != nil, let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func previewURL() -> URL? {
        let entries = HistoryStore.shared.entries
        guard !entries.isEmpty else { return nil }
        let selected = collectionView.selectionIndexPaths.first?.item ?? 0
        guard entries.indices.contains(selected) else { return nil }
        return entries[selected].url(in: HistoryStore.shared.directory)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}

extension HistoryWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL() == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        (previewURL() as NSURL?) ?? (NSURL() as QLPreviewItem)
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let index = collectionView.selectionIndexPaths.first,
              let cell = collectionView.item(at: index),
              let frame = cell.view.superview?.convert(cell.view.frame, to: nil),
              let window else { return .zero }
        return window.convertToScreen(frame)
    }
}

private final class HistoryCellView: MoliCardView {
    weak var imageView: NSImageView?
    var onHoverChanged: ((Bool) -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        imageView?.layer?.backgroundColor = MoliDesign.cardElevated.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    // MARK: - Native affordances: drag-out + right-click menu

    /// File URL for drag-out export (Finder, chat apps, mail).
    var dragFileURL: URL?
    /// Preview image drawn under the cursor during a drag.
    var dragPreview: NSImage?
    /// Builds the right-click menu; the cell selects itself first.
    var contextMenuBuilder: (() -> NSMenu?)?
    private var pressPoint: NSPoint?
    private var didBeginDrag = false

    override func mouseDown(with event: NSEvent) {
        pressPoint = event.locationInWindow
        didBeginDrag = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if !didBeginDrag, let start = pressPoint, let url = dragFileURL,
           hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 {
            didBeginDrag = true
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            draggingItem.setDraggingFrame(bounds, contents: dragPreview)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
            return
        }
        if !didBeginDrag { super.mouseDragged(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        pressPoint = nil
        if !didBeginDrag { super.mouseUp(with: event) }
        didBeginDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuBuilder?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

extension HistoryCellView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

final class HistoryCell: NSCollectionViewItem {
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopyImage: (() -> Void)?
    var onReveal: (() -> Void)?
    var onRightClick: (() -> Void)?
    private var entry: HistoryEntry?

    private let imgView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let deleteBtn = MoliHoverButton()
    private let openBtn = MoliHoverButton()

    override func loadView() {
        let v = HistoryCellView(
            frame: NSRect(x: 0, y: 0, width: 210, height: 164),
            fillColor: MoliDesign.card,
            borderColor: MoliDesign.hairline,
            cornerRadius: 12
        )
        view = v

        // Action buttons stay hidden until the card is hovered; hover also
        // lifts the card to the elevated surface color.
        v.onHoverChanged = { [weak self, weak v] hovered in
            guard let self, let v else { return }
            v.fillColor = hovered ? MoliDesign.cardElevated : MoliDesign.card
            v.applyStyle()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = MoliDesign.reduceMotion ? 0.01 : 0.15
                self.openBtn.animator().alphaValue = hovered ? 1 : 0
                self.deleteBtn.animator().alphaValue = hovered ? 1 : 0
            }
        }

        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.wantsLayer = true
        imgView.layer?.cornerRadius = 7
        imgView.layer?.backgroundColor = MoliDesign.cardElevated.cgColor
        imgView.layer?.masksToBounds = true
        v.addSubview(imgView)

        if let historyCellView = v as? HistoryCellView {
            historyCellView.imageView = imgView
        }

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = MoliDesign.secondaryText
        v.addSubview(label)

        configureActionButton(openBtn, symbol: "arrow.up.right.square", tooltip: L10n.text(.open), action: #selector(openTap))
        v.addSubview(openBtn)

        configureActionButton(deleteBtn, symbol: "trash", tooltip: L10n.text(.delete), action: #selector(deleteTap))
        v.addSubview(deleteBtn)

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(openTap))
        doubleClick.numberOfClicksRequired = 2
        v.addGestureRecognizer(doubleClick)

        NSLayoutConstraint.activate([
            imgView.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            imgView.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
            imgView.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
            imgView.heightAnchor.constraint(equalToConstant: 112),

            label.topAnchor.constraint(equalTo: imgView.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: openBtn.leadingAnchor, constant: -8),

            openBtn.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            openBtn.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -4),
            deleteBtn.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
        ])
    }

    func configure(with entry: HistoryEntry) {
        self.entry = entry
        openBtn.toolTip = L10n.text(.open)
        openBtn.setAccessibilityLabel(L10n.text(.open))
        deleteBtn.toolTip = L10n.text(.delete)
        deleteBtn.setAccessibilityLabel(L10n.text(.delete))
        imgView.image = HistoryStore.shared.image(for: entry)
        let df = DateFormatter()
        df.dateStyle = .short; df.timeStyle = .short
        label.stringValue = df.string(from: entry.timestamp)
        if let cellView = view as? HistoryCellView {
            cellView.dragFileURL = entry.url(in: HistoryStore.shared.directory)
            cellView.dragPreview = imgView.image
            cellView.contextMenuBuilder = { [weak self] in self?.makeContextMenu() }
        }
    }

    private func makeContextMenu() -> NSMenu {
        onRightClick?()
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            (L10n.text(.open), #selector(contextOpen)),
            (L10n.text(.copy), #selector(contextCopyImage)),
            (L10n.text(.showInFinder), #selector(contextReveal)),
            (L10n.text(.delete), #selector(contextDelete)),
        ]
        for (title, action) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func contextOpen() { onOpen?() }
    @objc private func contextCopyImage() { onCopyImage?() }
    @objc private func contextReveal() { onReveal?() }
    @objc private func contextDelete() { onDelete?() }

    private func configureActionButton(_ button: MoliHoverButton, symbol: String, tooltip: String, action: Selector) {
        button.layer?.cornerRadius = 6
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.alphaValue = 0  // revealed on card hover
    }

    @objc private func openTap() { onOpen?() }
    @objc private func deleteTap() { onDelete?() }
}
