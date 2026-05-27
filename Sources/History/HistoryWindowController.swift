import AppKit

final class HistoryWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate {

    private let collectionView = NSCollectionView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: L10n.text(.noScreenshotsYet))

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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = MoliDesign.secondaryText
        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    private func reload() {
        window?.title = L10n.text(.history)
        emptyLabel.stringValue = L10n.text(.noScreenshotsYet)
        emptyLabel.isHidden = !HistoryStore.shared.entries.isEmpty
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
            AppCoordinator.shared.openEditor(with: image)
            _ = self
        }
        item.onDelete = { HistoryStore.shared.delete(entry) }
        return item
    }
}

private final class HistoryCellView: MoliCardView {
    weak var imageView: NSImageView?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        imageView?.layer?.backgroundColor = MoliDesign.cardElevated.cgColor
    }
}

final class HistoryCell: NSCollectionViewItem {
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?

    private let imgView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let deleteBtn = NSButton()
    private let openBtn = NSButton()

    override func loadView() {
        let v = HistoryCellView(
            frame: NSRect(x: 0, y: 0, width: 210, height: 164),
            fillColor: MoliDesign.card,
            borderColor: MoliDesign.hairline,
            cornerRadius: 10
        )
        view = v

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
        openBtn.toolTip = L10n.text(.open)
        openBtn.setAccessibilityLabel(L10n.text(.open))
        deleteBtn.toolTip = L10n.text(.delete)
        deleteBtn.setAccessibilityLabel(L10n.text(.delete))
        imgView.image = HistoryStore.shared.image(for: entry)
        let df = DateFormatter()
        df.dateStyle = .short; df.timeStyle = .short
        label.stringValue = df.string(from: entry.timestamp)
    }

    private func configureActionButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
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
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    @objc private func openTap() { onOpen?() }
    @objc private func deleteTap() { onDelete?() }
}
